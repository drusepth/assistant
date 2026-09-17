<!-- decided -->
**D-listing-feeds. Events reach the app through listing sources the user attaches to a place — iCalendar feeds, pages carrying schema.org Event data, and opt-in keyed providers — polled on the reader's politeness rules; near is by construction and by arithmetic, never by geocoding**

The obvious build — ask the model for events near the user — fails the way
the reader's obvious build failed: the models this project argues for cannot
browse, a search that names the household's coordinates and interests is a
leak on a timer, and a model's prose about "this weekend" has no dates the
code can trust, nothing to dedupe and nothing to retire. So the split is
D-feed-reader's: finding the source is the user's job, with help; reading it
is the app's; judging it is the model's. A **ListingSource** belongs to a
place and is one of three kinds behind one seam: an **`ics`** feed
(`webcal:` rewritten, parsed by `Events::Import::Ics`, which gains `uid`,
`url` and `geo` on `ParsedEvent` additively); a **`page`** carrying schema.org
`Event` JSON-LD — the block Eventbrite, Meetup, venues and city calendars
publish for machines, read as structured data and never as prose, which
keeps it on the right side of D-no-keyword-logic; and, later and opt-in, a
**`provider`** — a keyed API such as Ticketmaster's Discovery API queried by
point, radius and window, deterministic HTTP rather than a model browsing
(so not Q9 either), switched on per place under a sentence saying it sends
the place's coordinates to a third party. `Listings::Discover` is
`Feeds::Discover` for calendars: `<link rel="alternate"
type="text/calendar">`, the JSON-LD, the conventional paths the common
calendar products expose, and a small tested table of host rewrites (a
Meetup group URL becomes its iCal export). Politeness is inherited whole —
conditional GET echoed raw, backoff capped at a day, everything through
`Web::Fetch`, only *adding* fetches in the request — with a 6-hour floor
instead of the reader's hour because listings are not news. What lands is a
**Happening**, not an `Event`: a candidate with its own table and verbs,
idempotent by `uid`, one row per occurrence sharing a `series_uid`, that
reaches the calendar only by "Add to calendar" or an accepted suggestion
(`event_id` then links them). **Near is by construction, then by
arithmetic**: a happening is at its source's place unless it carries a point
(iCal `GEO`, JSON-LD `location.geo`, a provider's venue), in which case the
haversine `Datasets::Places` already has gives its distance and a row beyond
the radius is kept but marked out of range; an address string is never
turned into a point by anything. Titles and descriptions are stripped to
text at parse time and URLs refused unless `http(s)`, the reader's hostile-
input posture. Design in `docs/EVENT_RADAR_PLAN.md` §4 and §8. — *Not
started.*
