#!/usr/bin/env python3
"""
Build PATSTAT 2019 granted country-industry IO using CPC→ISIC mapping.

Inputs in --input-dir:
- cpc_isic_mapping_draft.csv
- PATSTAT_CPC_with_citations.csv
- PATSTAT_CPC_no_usable_citations.csv

Outputs:
- PATSTAT_2019_granted_country_industry_IO_CPC_ISIC_long.csv
- PATSTAT_CPC_ISIC_QC_summary.csv
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from decimal import Decimal, getcontext
from pathlib import Path

getcontext().prec = 28


def read_csv_auto(path: Path):
    text = path.read_text(encoding="utf-8-sig", errors="replace")[:8192]
    try:
        dialect = csv.Sniffer().sniff(text, delimiters=",;\t")
        delimiter = dialect.delimiter
    except Exception:
        delimiter = ";" if text.count(";") > text.count(",") else ","
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f, delimiter=delimiter)
        return list(reader), reader.fieldnames or []


def clean(value: object) -> str:
    return str(value or "").strip().strip('"').upper()


def dec(value: object) -> Decimal:
    s = str(value if value is not None else "0").strip().replace(",", "")
    if s == "":
        s = "0"
    return Decimal(s)


def write_dicts(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            out = {}
            for key in fieldnames:
                value = row.get(key, "")
                out[key] = format(value, "f") if isinstance(value, Decimal) else value
            writer.writerow(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    mapping_rows, _ = read_csv_auto(input_dir / "cpc_isic_mapping_draft.csv")
    with_rows, _ = read_csv_auto(input_dir / "PATSTAT_CPC_with_citations.csv")
    no_rows, _ = read_csv_auto(input_dir / "PATSTAT_CPC_no_usable_citations.csv")

    # CPC4 -> [(ISIC2, weight)]
    mapping = defaultdict(list)
    for row in mapping_rows:
        cpc4 = clean(row.get("cpc_4digit"))
        isic = clean(row.get("isic_2digit"))
        weight = dec(row.get("weight"))
        if cpc4 and isic and weight > 0:
            mapping[cpc4].append((isic, weight))

    def mapped_isic(cpc4: str):
        cpc4 = clean(cpc4)
        if cpc4 == "NO_USABLE_PATENT_CITATION":
            return [("NO_USABLE_PATENT_CITATION", Decimal("1"))]
        if cpc4 == "NO_CPC" or cpc4 == "":
            return [("NO_ISIC", Decimal("1"))]
        if cpc4 not in mapping:
            return [("NO_ISIC", Decimal("1"))]
        return mapping[cpc4]

    agg = defaultdict(Decimal)
    unmapped_cpc = defaultdict(Decimal)

    for source_rows in (with_rows, no_rows):
        for row in source_rows:
            input_country = clean(row.get("input_cited_country"))
            output_country = clean(row.get("output_citing_country"))
            input_cpc = clean(row.get("input_cited_cpc4"))
            output_cpc = clean(row.get("output_citing_cpc4"))
            edge_weight = dec(row.get("io_weight"))

            input_map = mapped_isic(input_cpc)
            output_map = mapped_isic(output_cpc)

            if input_cpc not in mapping and input_cpc not in ("NO_USABLE_PATENT_CITATION", "NO_CPC", ""):
                unmapped_cpc[input_cpc] += edge_weight
            if output_cpc not in mapping and output_cpc not in ("NO_USABLE_PATENT_CITATION", "NO_CPC", ""):
                unmapped_cpc[output_cpc] += edge_weight

            for input_isic, input_w in input_map:
                for output_isic, output_w in output_map:
                    key = (input_country, input_isic, output_country, output_isic)
                    agg[key] += edge_weight * input_w * output_w

    final_rows = [
        {
            "input_cited_country": key[0],
            "input_cited_isic": key[1],
            "output_citing_country": key[2],
            "output_citing_isic": key[3],
            "io_weight": value,
        }
        for key, value in sorted(agg.items())
    ]

    write_dicts(
        output_dir / "PATSTAT_2019_granted_country_industry_IO_CPC_ISIC_long.csv",
        final_rows,
        ["input_cited_country", "input_cited_isic", "output_citing_country", "output_citing_isic", "io_weight"],
    )

    total = sum(row["io_weight"] for row in final_rows)
    raw_total = sum(dec(r.get("io_weight")) for r in with_rows) + sum(dec(r.get("io_weight")) for r in no_rows)

    qc_rows = [
        {"metric": "raw_PATSTAT_CPC_IO_total", "value": raw_total},
        {"metric": "final_CPC_ISIC_IO_total", "value": total},
        {"metric": "difference_final_minus_raw", "value": total - raw_total},
        {"metric": "final_rows", "value": len(final_rows)},
        {"metric": "unmapped_distinct_cpc4_count", "value": len(unmapped_cpc)},
    ]
    write_dicts(output_dir / "PATSTAT_CPC_ISIC_QC_summary.csv", qc_rows, ["metric", "value"])

    unmapped_rows = [
        {"cpc4": cpc, "io_weight": weight}
        for cpc, weight in sorted(unmapped_cpc.items(), key=lambda kv: (-kv[1], kv[0]))
    ]
    write_dicts(output_dir / "PATSTAT_CPC_ISIC_unmapped_cpc4.csv", unmapped_rows, ["cpc4", "io_weight"])

    print("Done.")
    print(f"Raw PATSTAT CPC IO total: {raw_total}")
    print(f"Final CPC→ISIC IO total: {total}")
    print(f"Difference: {total - raw_total}")
    print(f"Rows: {len(final_rows):,}")
    print(f"Unmapped CPC4 count: {len(unmapped_cpc):,}")


if __name__ == "__main__":
    main()
