# Teacher-facing clarification

The final industry version should be regenerated using the previous CPC→ISIC mapping file:

- `cpc_isic_mapping_draft.csv`

The previously generated `patent_isic_mapping.csv` and `country_industry_io_long.csv` from the old zip should not be used as final results because they were generated under the old Google/publication-level workflow. The mapping file itself can be reused, but the PATSTAT 2019 granted patent data must be exported again with CPC information.

PATSTAT data are not exactly identical to Google Patents. Earlier checks showed that Google Patents 2019 granted application count and PATSTAT 2019 granted application count differ by country and in total. Therefore the final denominator and final IO should use PATSTAT as the source of truth.

For CPC in PATSTAT, the current EPO data catalog notes that CPC symbols are now assigned to DOCDB families, with `tls225_docdb_fam_cpc` used for family-level CPC and `tls224_appln_cpc` retained for downward compatibility. Therefore these SQL files use `tls225_docdb_fam_cpc`.
