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
- `places.csv` — ~7,300 settlements (Natural Earth 1:10m populated places,
  public domain), the gazetteer the photo map names its pins from
  (`docs/TRAVEL.md`). This one has **no fetch and needs none**: settlements
  aren't revised annually, and the whole point is that naming a photo's
  location never leaves the box. Regenerate with
  `ruby script/build_places_dataset.rb`, or import a denser
  `name,country,latitude,longitude,population` CSV at `/admin` — an instance
  that wants the villages a 7,000-entry gazetteer misses doesn't have to wait
  for a release.

- `pet_toxics.csv` — household items that poison pets (US FDA consumer
  updates and CVM pet-poison advisories, US government work, public domain),
  read by the pet-care chat before any model speaks (`docs/PETS_PLAN.md` §6).
  Like `places.csv` it has **no fetch and needs none**: the list is short and
  stable, and the whole point is that "can he have this?" is answered the same
  way every time rather than by a model that is right 98% of the time about
  something with a fatal tail. A missing or malformed file leaves an empty
  list, never an exception — the emergency notice beside it is code-authored
  and does not depend on the data.

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
