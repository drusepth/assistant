<!-- decided -->
**D-nonclinical-care-kinds. The care radar tracks non-clinical upkeep too — starting with the haircut — as a flagged kind, not a second system.**
A haircut is not health, but it is the same *shape* as everything the radar
already does: a recurring appointment on a rhythm you'd rather not keep in your
head, whose whole question is "when was the last one, and is one booked?" So it
ships as one more entry in `Health::CareRadar::KINDS` (haircut / 2mo, matching
`haircut`, `hair …cut|trim|appointment`, `barber`, `hairdress`, `hair salon`,
`stylist`) rather than as a grooming feature with its own storage — which means
CalDAV sync, imports, quick capture, the "Counts as" override, household care,
and the Tune page all carry it for free, and muting it is the same checkbox as
muting vision. Grooming sorts last, after the care that matters more.

What the kind carries is a `clinical:` flag (default true, so every existing
kind and every user-defined custom kind is unchanged), and the flag governs
exactly the medical next-clicks: a non-clinical tile offers no "Find a provider"
(find-care is a find-a-*doctor* tool, and pointing it at a barber would be the
invented-cardiologist lie in miniature) and no "Prep for this visit"; the
cadence watcher's nudge accepts into a plain task instead of find-care; and copy
names the thing itself ("Last haircut Feb 2026", "No haircuts on record yet",
"your last haircut was February 2026") rather than calling it a visit. Two
derived methods on `Kind` — `visit_noun` and `history_phrase` — keep every line
of clinical copy byte-identical.

The one honest limit: intervals are whole months (`due_on = last >> n`), so a
six-week rhythm rounds to two and shows due about two weeks late. Sub-month
cadence would mean an `interval_days` column and a Tune page that speaks weeks —
worth doing when a second kind wants it, not for the first.
