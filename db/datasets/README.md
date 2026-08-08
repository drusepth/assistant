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

## When the fetch fails

Whatever goes wrong is on the Public datasets card at `/admin` — dated, with
the message — and in the error log under `dataset_refresh:*` (fetch) or
`dataset_import:*` (file import).

`bls.gov refused every request with HTTP 403` is not a missing file. BLS
fronts its downloads with an edge that turns away clients and networks it
doesn't like — datacenter and non-US addresses among them — so plenty of
self-hosted instances can never fetch, no matter how many times the button is
pressed. The fix is the import path, which works from anywhere: download
`oesmYYnat.zip` from <https://www.bls.gov/oes/tables.htm> on a machine that
can reach BLS, then Import file on `/admin`. CPI accepts a `year,value` CSV
the same way.
