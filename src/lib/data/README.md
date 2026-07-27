# ZIP lookup data

`zcta-2025.json` is generated from the United States Census Bureau's 2025
ZIP Code Tabulation Areas Gazetteer file.

- Source: https://www.census.gov/geographies/reference-files/time-series/geo/gazetteer-files.2025.html
- Record layout: https://www.census.gov/programs-surveys/geography/technical-documentation/records-layout/gaz-record-layouts/gaz25-record-layouts.html
- Generated with: `node scripts/build-zcta-data.mjs <2025_Gaz_zcta_national.txt>`

ZCTAs are approximate geographic representations of USPS ZIP delivery areas.
Not every valid USPS ZIP code is represented by a ZCTA.
