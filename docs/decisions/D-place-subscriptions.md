<!-- decided -->
**D-place-subscriptions. A place is something you subscribe to: a gazetteer-named point with a radius and a lead time, standing or dated by a trip's stay — per user, never geocoded, never shared**

The ask behind `docs/EVENT_RADAR_PLAN.md` is "events near the places I care
about", and the first thing it needs is a *place* the app can hold. Not the
household address — that is free text a human typed for letters, and polling
on the strength of a silent parse of it is the wrong kind of helpful — and
not a point from a geocoding service, which the app has refused three times
(D-travel-facet's "when a map wants data, ship the data"). A `Place` is a
name the user typed, resolved through `Datasets::Places.current.named` —
the same call `Stay` makes on save (D-stay-pins) — to the 7,300-settlement
public-domain gazetteer already in the repo, refused with the nearest
suggestions when the file doesn't know it. It carries exactly two knobs: a
**radius** (default 40 km) that decides which of a source's events count as
here when they carry their own coordinates, and a **lead time** (default 14
days) that decides how far ahead the watcher may interrupt; there is no
importance slider, because the model's judgment plus the user's corrections
is the whole ranking. A place is **per user and never shared** — a declared
interest in a location is what D9 keeps private by default and Q14 keeps
coordinates from crossing users — and two members who both want the same
town each add it, with the fetch deduped by URL so the publisher pays once.
Home is *offered*, prefilled from the household address's last line, and
confirmed by the user. An upcoming located `Stay` on a trip the user is on
is a **dated place** — the stay's point, the default radius, check-in to
check-out as both window and lead — with no row of its own, so "what's on
in Lisbon while we're there" needs nothing but the trip the household
already planned. Design in `docs/EVENT_RADAR_PLAN.md` §3. — *Built 2026-09 (W1, W5). A stay is a dated place by matching it against the user's own places (`Radar::Windows`), since a source needs a place to hang off; the trip page offers an unplaced stay as one click to add.*
