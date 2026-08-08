# Bundled public datasets (D-public-datasets)

Seed snapshots of public-domain statistics the Career tools read locally —
no scraping, no per-user web calls. The lookup order everywhere is
`storage/datasets/` (written by `RefreshDatasetsJob` or an admin file
import) first, then these seeds; consumers always surface the data's
as-of year.

- `cpi_u.csv` — CPI-U annual averages (BLS series CUUR0000SA0). Powers the
  real-terms-drift watcher and the raise case's buying-power math.
- OES/OEWS national wage medians ship **without** a seed (the table is large
  and revised annually): `/admin` can fetch it from bls.gov when the
  instance's network allows, or import the downloaded `oesmYYnat` file on
  air-gapped installs.
