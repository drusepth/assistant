# EVENT_RADAR_PLAN.md — events near you, that you'd actually go to

`docs/HOBBIES.md` §3 asked for "find meetups nearby" and §4 for an **event
radar** — local happenings, releases, exhibits — and parked both behind Q9,
the open question about tools that need the live web. What shipped was the
honest half: `Tool::FindYourPeople` tells you where people who share a hobby
gather and forbids itself from naming a single real club, because the model
cannot browse. That is the right tool for a model that cannot see, and it is
not what the household asked for. The ask is: **tell me, ahead of time, about
events near the places I care about that I would likely want to go to, judged
by my hobbies and interests.**

This plan builds that without waiting on Q9, by the same move the reader made
(`docs/READER.md`, **D-feed-reader**): the app does not go looking for events;
the user points it at the calendars that publish them, the app polls those
politely, and the model — which cannot browse but can read — decides which of
the events it is holding are worth an interruption. Three decisions:

- **D-place-subscriptions** — a *place* is something you subscribe to: a
  named point from the gazetteer with a radius and a lead time, standing
  (home, the town you drive to on weekends) or dated (a stay on an upcoming
  trip). Coordinates come from the dataset the app already ships, never from
  a geocoding service.
- **D-listing-feeds** — events reach the app through *listing sources*
  attached to a place: iCalendar feeds, pages carrying schema.org `Event`
  data, and (later, opt-in) keyed provider APIs. "Near" is by construction —
  a source belongs to a place — and by arithmetic when an event carries its
  own coordinates. Nothing is geocoded, nothing is scraped from prose.
- **D-event-radar** — the model reads the events, batched and once each,
  against the closed set of the user's hobbies plus one sentence of interest
  the user owns; matches surface on the hub and the hobby pages, and a
  watcher proposes the ones inside a place's lead time as suggestions that
  retire when the date passes. With no model configured, the listings still
  show, sorted by date, and the matching says it is off.

## 1. What changes, in one paragraph

A new **Places** surface lets a user name the places whose events they want to
hear about — "Tulsa", "Grandma's town", the Lisbon stay in March — and, under
each, follow the calendars that publish what's on there: the city's events
feed, the library, the climbing gym's Meetup group, the venue whose page lists
its shows. Those sources are polled on the reader's politeness rules, and
every event they publish lands as a **happening**: not an Event on your
calendar, but a candidate — dated, placed, linked. The Hobbies hub grows a
"Near you" card and `/happenings` is the full river, upcoming and by date,
with "Add to calendar" and "Not this" on every row. Behind it, once a model is
configured, `Radar::Match` reads each new happening against your hobbies and
your one-line brief and marks the ones it thinks are yours, with a sentence
saying why. `Watcher::EventRadar` then turns matches inside each place's lead
time into suggestions — the ordinary D20 kind, in Attend and on the Dashboard,
and on your phone if Hobbies is set to Active — and each one retires the day
the event passes. Accepting puts the event on your calendar, tagged with the
hobby it matched. Dismissing tells the matcher it was wrong.

## 2. Why sources, not search

The obvious build is the one HOBBIES.md deferred: ask the model for events
near the user. It fails three ways, and the failures are the reasons the
reader was built the way it was.

**The model cannot see.** Nothing in this app assumes the configured model
can browse (`docs/ROADMAP.md` → capability honesty), and the models this
project argues for — local ones — never will. A feature that only works on
one hosted provider's browsing mode is not a feature of this app.

**A search is a leak.** "Events near 36.15, -95.99 for someone into birding
and jazz" is the household's location and interests, sent to a third party,
on a timer, forever. The app's whole premise is that this stays home. Polling
a public calendar the user chose sends nothing about the user but the
request itself, from a user agent that says what it is.

**Search results are not a data model.** A model's prose about "events this
weekend" has no dates the code can trust, no way to say "you saw this one
already", nothing to retire, nothing to dedupe. An iCalendar feed has all of
that, by standard, and every city, library, venue, university and Meetup
group publishes one. So do schema.org `Event` blocks on ordinary event pages —
Eventbrite, Meetup, most venue sites and most city calendars embed them, and
they carry name, start, end, venue, address, coordinates and a link, as
structured data, for exactly this use.

So the split is the reader's: **finding the source is the user's job, with
help; reading it is the app's; judging it is the model's.** The help matters
and §4 is about it — an empty "paste a calendar URL" box is the RSS problem
all over again — but the line holds, and it is what lets this ship on a
model-less instance, on a locked-down box, and on Ollama.

The one place a *search* honestly belongs is a keyed provider API
(Ticketmaster's Discovery API takes a point, a radius and a date range and
answers with structured events). That is deterministic HTTP, not a model
browsing, so it is not Q9 either — but it does send a location to a third
party, so it is opt-in, per place, with that sentence on the switch. §8.

## 3. Places (D-place-subscriptions)

A **Place** is the unit of subscription: something the user says they care
about what happens near.

```
Place        user_id, name, latitude, longitude (decimal 10,6), radius_km (int, 40),
             lead_days (int, 14), alerts (bool, true), position
```

- **Named from the gazetteer, never geocoded.** Typing "Tulsa" resolves
  through `Datasets::Places.current.named` — the same call `Stay` already
  makes on save (**D-stay-pins**) — to the 7,300-settlement public-domain
  file the app ships. A name the gazetteer doesn't know is refused with the
  nearest suggestions, not sent anywhere. This is the D-travel-facet rule
  held: *when a map wants data, ship the data.* A denser dataset dropped into
  `storage/datasets/` widens what can be named without touching code.
- **Radius and lead time are the two knobs**, and they are the only two.
  Radius (default 40 km) decides which of a source's events count as "here"
  when an event carries coordinates (§5). Lead time (default 14 days) decides
  how far ahead the watcher will interrupt you; the river shows further.
  There is no "importance" slider — the model's judgment plus the user's
  corrections is the whole ranking, and D-feed-reader's lesson about scores
  applies twice to something that will notify you.
- **Per user, never shared.** A place is a declared interest in a location,
  which is exactly the kind of thing D9 says stays private by default, and
  Q14 says coordinates never cross users. Two household members who both
  want Tulsa each add Tulsa; a source is one URL and the poll dedupes by URL
  across the household (§5), so the cost is one row, not one fetch. Sharing
  a place is in §9.
- **Home is offered, not assumed.** The Places page's empty state offers
  "Add where you live" prefilled from the last line of the household address
  (`households.address` → gazetteer), and the user confirms it. The address
  is free text a human typed for letters; resolving it silently and polling
  on the strength of the guess is the wrong kind of helpful.
- **A trip's stay is a dated place.** Wave 4 (§7) makes each upcoming `Stay`
  that has coordinates a window the radar reads — check-in to check-out, at
  the stay's point — without a Place row, so "what's on in Lisbon while
  we're there" needs nothing but the trip the household already planned.

## 4. Listing sources (D-listing-feeds)

A **ListingSource** belongs to a place and is where its happenings come from.

```
ListingSource  place_id, url, kind (ics | page | provider), provider (string, nullable),
               title, active, etag, last_modified (raw), last_fetched_at, last_item_at,
               failure_count, last_error, settings (json), credentials (encrypted)
```

### 4.1 Three kinds, one seam

- **`ics`** — an iCalendar feed. `webcal://` is rewritten to `https://`.
  Parsed by `Events::Import::Ics`, which already handles folding, TZID,
  all-day spans, DURATION, cancelled events, RRULE expansion inside a window,
  EXDATE and RECURRENCE-ID overrides — everything a public calendar throws.
  Two additive changes to the parser: `ParsedEvent` gains `uid`, `url` and
  `geo`, which the calendar import ignores (it folds the link into the
  description today and keeps doing so) and the radar keeps.
- **`page`** — a web page carrying schema.org `Event` structured data
  (JSON-LD, the form Google's event search requires, so publishers keep it
  correct). `Listings::Parse::Schema` walks every `<script
  type="application/ld+json">` block, takes objects whose `@type` is `Event`
  or a subtype, and reads `name`, `startDate`, `endDate`, `url`,
  `location.name`, `location.address`, `location.geo`, `eventStatus`
  (cancelled and postponed are honored) and `@id`/`url` as the uid. A venue's
  "upcoming shows" page, a Meetup group's events page and an Eventbrite
  organizer page are each one source this way. Parsing structured data is
  deterministic, so it is on the right side of **D-no-keyword-logic**: the
  page's *prose* is never read for dates or names, only the block the
  publisher wrote for machines.
- **`provider`** — a keyed API queried by the place's point and radius
  (§8). Same table, same politeness, same happenings; the difference is what
  the URL is and the fact that the request names a location.

Everything above `Listings::Refresh` is kind-blind: a source yields a list of
parsed events, and the ingest is the same.

### 4.2 Discovery: paste anything

`Listings::Discover` is `Feeds::Discover` for calendars, and the recipes are
the feature, because nobody knows their library's iCal URL by heart:

- a `.ics`/`webcal:` URL, or a body starting `BEGIN:VCALENDAR`, is an `ics`
  source as-is;
- a page is fetched once (`Web::Fetch.raw`, size-capped, SSRF-guarded) and,
  in order: `<link rel="alternate" type="text/calendar">` wins as `ics`;
  otherwise any `Event` JSON-LD on the page makes it a `page` source;
  otherwise the conventional paths (`/calendar.ics`, `/events.ics`,
  `/events/ical`, `/?ical=1` — Localist, Trumba, The Events Calendar,
  CivicPlus and LibCal between them cover most cities and libraries) are
  tried, capped like the reader's guesses;
- **known hosts are rewritten**, the way the reader rewrites a subreddit to
  its RSS: a Meetup group URL becomes that group's iCal export, a public
  Google Calendar embed becomes its `.ics`, an Eventbrite organizer page is
  kept as a `page` source. The table is small, hand-maintained and tested,
  and it is a URL rewrite, not a classification.

Nothing found → the form says what it tried and what a calendar link looks
like, and offers the per-place help card (§6.3) instead of a dead end.

### 4.3 Politeness, inherited

This is the second part of the app that polls strangers' servers on a timer,
and it inherits the reader's rules whole rather than re-deriving them:
conditional GET with the publisher's `ETag`/`Last-Modified` echoed raw;
exponential backoff on failure capped at a day; every fetch through
`Web::Fetch` (private ranges refused, redirects capped, bodies capped —
8 MB, the reader's ceiling, since a year of a city's calendar is big); only
*adding* a source fetches in the request, every other check is a job. Two
numbers differ because listings are not news: the floor is **6 hours**, not
one (an event calendar that changed in the last hour is rare and the change
is rarely urgent), and a source nobody has opened in a month drops to daily.
`RefreshListingsJob` rides `config/recurring.yml` beside `refresh_feeds`.

One source, many subscribers: `listing_sources` is unique on `(place_id,
url)`, but the fetch is keyed on the URL, so two household members following
the same city calendar cost the publisher one request per interval.

### 4.4 Happenings: candidates, not events

```
Happening   listing_source_id, uid, series_uid, title, description (text, plain),
            location, url, latitude, longitude, starts_at, ends_at, all_day,
            distance_km, out_of_range (bool), event_id (nullable), hidden_at,
            matched_at
```

A happening is **not an `Event`**. The calendar is the user's own life, and
D-feed-reader's line about stories applies: nothing lands on it without a
click. So happenings have their own table and their own verbs, and an
`Event` is created from one only by "Add to calendar" or by accepting a
suggestion — at which point `event_id` links them, so the row can say "on
your calendar" and the watcher can tell handled from ignored.

- **Idempotent by `uid`**, like feed items by guid: a re-listed happening
  keeps its matches, its hidden state and its link to the event you made.
  A recurring rule yields one happening per occurrence, each with the
  master's `series_uid`, and §5 uses that so a weekly meetup is judged once,
  not fifty-two times.
- **Near is by construction, then by arithmetic.** A happening from a source
  attached to Tulsa is *in Tulsa* unless it says otherwise. When it carries
  coordinates (iCal `GEO`, JSON-LD `location.geo`, a provider's venue) the
  haversine `Datasets::Places` already has gives `distance_km`, and a row
  outside the place's radius is kept but marked `out_of_range` — hidden from
  the river and never matched, visible under a fold on the source's page so
  a wrong radius is diagnosable. An address string is *never* turned into a
  point: no geocoder, and no model guessing coordinates from "Cain's
  Ballroom" (**D-travel-facet**'s "confidently wrong Paris" rule).
- **Past is pruned.** A happening whose end passed more than 30 days ago is
  deleted unless it is linked to an event; the radar is not an archive, and
  the calendar keeps what you kept. Matches go with it.
- **Hostile input, handled where the reader handles it.** Titles, locations
  and descriptions are stripped to plain text at parse time (`Nokogiri` text
  for anything HTML-shaped, entity expansion off, `nonet`), URLs are refused
  unless `http(s)` in the parser, `uid` is truncated, and nothing downstream
  holds a string it could be tempted to mark safe. A stranger's calendar can
  put words in a row; it cannot put markup on the page or a request in the
  app.

## 5. The match (D-event-radar)

"Would this person want to go to this?" is the question, and it is a judgment
about an open subject — which means, per **D-no-keyword-logic**, the model
answers it or nobody does. There is no vocabulary, no "contains *bird*", no
category taxonomy from the provider used as a shortcut. The shape is
`Feeds::RouteStories`'s, because that is the shape every classifier in the
app shares: batched, once each, capped per run, validated into a closed set
of rows the code already holds.

### 5.1 Targets: what the model can say

The closed set the model selects from is built by `Radar::Targets`:

- **every hobby lens** the user has (`Hobbies::MapFeeds.askable_lenses`, so
  Other Interests is never offered), each with its `HobbyBrief` beside its
  name — the one or two lines saying what the hobby *means* to this person,
  which **D-story-matching** already keeps per user;
- **one radar brief** (`users.radar_brief`, ≤ 600 chars) as the target
  `household`: the sentence for everything that isn't a hobby. "Two kids
  under six, we like farmers' markets, free outdoor concerts and anything at
  the science museum; not bars, not late nights." Prose the user owns, the
  same way a hobby brief is — nothing compares it to anything, so it can't
  be wrong the way a rule can. The model drafts one from the hobby briefs
  and what the user has read in the reader, and a sentence the user wrote
  is never overwritten (`Feeds::Briefs::Author`'s rule, reused).

The answer per happening is *one target or leave it out*, plus one sentence
of why. Leaving it out is the right answer for most rows, and the prompt says
so; the arithmetic in §5.3 depends on it.

Wave 5 widens the set with active **Education subjects** (`subjects.title` +
`interest_frame`), so a planetarium talk reaches a kid's astronomy course —
another lens dividend, and a prompt change plus one more branch in
`Targets`, not a schema change.

### 5.2 One question per series, once

`Radar::Match` takes the user's unmatched happenings that are upcoming, in
range and not hidden — **one per `series_uid`**, oldest first — in batches
of twenty, with title, first 300 characters of description, venue, the
place's name and the date, and writes the answer to every occurrence in the
series. `matched_at` is stamped whether or not anything matched, so a row is
read once; a new hobby, a changed brief or a "Not this" clears it for a
bounded resweep (the last 30 days of arrivals, capped), the way
`Feeds::RouteStories.resweep!` does. The cap per run is 200 rows — ten
calls — and a run only ever happens in a job with `RetriesModelCalls`.

```
HappeningMatch   happening_id, target (string: "section:12" | "household"), section_id (nullable),
                 reason (≤ 200), source (model | hand), rejected_at
```

Unique on `(happening_id, target)`. `section_id` is denormalized from the
target for the joins the hobby pages make; `target` is the closed-set key
the model actually chose, and a key that isn't in the set the run was given
is dropped before anything is written.

### 5.3 The arithmetic, honestly

A place with four sources — a city calendar, a library, a Meetup group and a
venue — publishes on the order of 40–120 upcoming happenings at any time,
and gains maybe 20–40 new series a week. Three places is ~100 new rows a
week, five batches, five model calls. A household with no places spends
nothing; a household with no model spends nothing and is told so. This is
the "ask about less" route to affordability: new series only, once each,
inside the radius, and never the occurrences.

Two things it deliberately does not do to save more: it does not pre-filter
by a provider's category (that is a keyword list someone else wrote), and it
does not skip sources the user "probably" isn't interested in — a source was
followed on purpose.

### 5.4 Corrections are examples

"Not this" on a happening tombstones the match (`rejected_at`), retires any
suggestion built on it, and puts the title in the next batch's prompt under
*the user says these are NOT {target}* — the correction loop
`Feeds::RouteStories` runs, verbatim. Dismissing a radar suggestion does the
same thing through a new, default-no-op `Watcher::Base#dismissed(suggestion)`
hook, so the two ways of saying no teach the same lesson. There is no "more
like this": a positive vote is a rating mechanic, and the positive signal
is the brief, which the user can edit in a sentence.

### 5.5 With no model configured

Sources poll, happenings land, the river shows everything by date, "Add to
calendar" works, and every surface that would show a match shows one line
instead: *No model is configured, so nothing here is matched to your
hobbies — everything near each place is listed by date.* No watcher runs (a
suggestion with no judgment behind it is a newsletter). That is the same
reduction the reader accepted, and for the same reason: an honest list beats
a plausible guess, and a local model does this job for free.

## 6. Surfaces

### 6.1 The hub card and the hobby pages

`Sections::Panels::Hobbies` gains a memoized `radar` (batched across places,
never per card, like `rows`) and `_hobbies.html.erb` renders one **Near
you** card after the hobby grid: the next few matched happenings across all
places, date-first, each with its hobby chip and the model's sentence on
hover, and "See what's on →" to `/happenings`. A household with no places
gets a one-line doorway to Places instead of a card. Nothing in
`SectionsController`, `sections/show.html.erb` or `SectionsHelper` changes
(D37).

`Sections::Panels::HobbiesLens` gains `nearby`: matched happenings for
*this* hobby, upcoming, with the same verbs — the "Birding, near you" list
the whole feature exists to produce, on the page where someone has already
decided to spend time on birding.

### 6.2 `/happenings`, the river

The everything-view, in the reader's density: upcoming, by date, grouped by
day, filtered by place, by hobby (matches only) or by source, with "matched
only" on by default when a model is configured and absent when it isn't.
Each row: date and time, title, venue and distance when known, the place
chip, the hobby chip and its reason, and the verbs:

- **Add to calendar** — creates the `Event` from the row (title, start, end,
  all-day, location, description with the link), tagged Hobbies and the
  matched lens (and Travel inside a trip window), links `event_id`, and the
  row shows "on your calendar". A direct write on a click, like "Make a
  task" in the reader.
- **Not this** — §5.4. Undo restores.
- **Hide** — for the thing you're simply not going to; no lesson taught.
- the link out, `rel="noopener noreferrer nofollow"`.

Turbo replaces the row on each verb, the reader's `act` pattern, HTML
fallback redirects to the river.

### 6.3 Places

`/places`: the user's places as cards — name, radius, lead time, alert
switch, the sources under it with the reader's health tell (green, backing
off, failing since), what's on next — and, per place, the paste box and a
**where calendars hide** help card: the city's site (look for "subscribe"
or an iCal icon), the library, park districts, the university, the venue's
"upcoming" page, a Meetup group's events page, the museum. The card is
static copy plus the rewrite recipes §4.2 knows, per kind of institution —
not a search, and not a list of specific local institutions the app would
be guessing at.

`Tool::FindYourPeople` and the planned "Find a class" learn one new
follow-up shape: *follow the listings* — when the draft names a kind of
organization, its check-this-week task links to `/places` with the place
prefilled. This is HOBBIES.md's "upgrades in place when Q9 resolves" landing
without Q9: the tool still never names a real club, but the user who finds
one now has somewhere to point it.

### 6.4 Settings

The **Hobbies** dial governs the watcher, as it governs everything under
Hobbies: *Off* → no suggestions; *Quiet* → weekly, in-app; *Active* → daily,
and the phone hears about it (§7.1). Per place, `alerts` turns the watcher
off for that place without unfollowing anything (the town you visit twice a
year is worth a river, not a nudge), and `lead_days` sets how far ahead. The
radar brief is edited on `/places` and on the hobby brief card, with the
same "draft one for me" button and the same rule that a written one wins.

## 7. The watcher (D-event-radar, continued)

`Watcher::EventRadar` (`section_slugs: %w[hobbies]`) is SQL over
`happening_matches`: live matches whose happening starts inside the owning
place's `lead_days`, is in range, not hidden, not linked to an event, and
whose suggestion doesn't exist yet. It proposes at most **five per place per
scan**, soonest first, and never more than one per series (the Tuesday walk
is one suggestion, expiring and re-proposable per occurrence bucket, not
one per Tuesday).

- **Fingerprint** `happening:<id>` — the subject is a row, so
  `subject_id` works and nothing re-proposes a dismissed one.
- **Title** is date-first — *Sat 3 Oct · Fall Bird Walk, Lakeside Park
  (Birding, 9 km)* — because a date is a commitment and a name is a pile.
  **Body** is the model's sentence, the venue and the time.
- **Action** `{ "happening" => id, "expires_on" => date, "accept_label" =>
  "Add to calendar" }`. `Suggestion#materialize` learns the `happening` key
  and creates the `Event` from the row exactly as the river's verb does —
  one path, so the calendar event is identical whichever way it arrived.
  The payload carries an id rather than a copy of the fields, so a
  publisher's correction (new time, cancelled) reaches the click.
- **Retires** on `expires_on` for free (**D-suggestion-lifecycle**), and
  `resolved?` opts in for three more: the match was rejected, the happening
  was hidden or cancelled, or the row is now linked to an event — you added
  it yourself from the river, and a nudge about a thing on your calendar is
  the D-reminders failure restated.
- **Trip windows** (Wave 4): for each upcoming located `Stay` on a trip the
  user is on, the same query runs with the stay's point, the trip's radius
  (40 km, the place default) and the stay's dates as both window and lead —
  proposed under Hobbies *and* Travel, so the trip page's "While you're
  there" and the hub's card show the same rows. A stay has sources only if
  someone followed some (the trip page offers the paste box and the recipes
  for the destination) or a provider is on — which is the strongest
  argument for §8.

### 7.1 Notifying

Nothing new. Active sections' proposals already leave the app through
`NotifyJob` (**D22**: webhook, Web Push, email if configured, SMS/Signal
where set up), batched per scan, titles only, with a signed decision link
(**D-decision-links**) so the phone can accept from the lock screen — and
"Add to calendar" is exactly the one-tap decision that link was built for.
Quiet stays in-app: Attend zone, Dashboard feed, the weekly digest line.
The daily cadence is already Active-only, which is what makes a 14-day lead
time honest at that dial and a weekly one honest at Quiet.

### 7.2 Preparation

Not applicable, and said so: `accept` creates a row from data the app
already holds, so there is nothing for **D-agent-prepared-work** to draft.
If a later wave adds "plan the outing" (who to invite from People, the
drive, the ticket task), that is a plan tool, and the prepared-work seam is
there.

## 8. Providers: the opt-in search

Everything above works from calendars the user found. What it cannot do is
answer for a place nobody has followed anything for — which is every trip
destination on the first day. A **provider** source fills that: a keyed API
queried by point, radius and window, returning structured events.

- **`Listings::Providers::Ticketmaster`** first (Discovery API: free key,
  lat/long + radius + date range, venue coordinates and links in the
  answer). Concerts, sports, theatre — the paid-ticket world, which is also
  the world no city calendar covers. Registered in a `PROVIDERS` hash on
  the model, one entry per provider (the D26 registry shape), each naming
  its fields and the sentence for its switch.
- **Opt-in, per place, with the sentence on the switch**: *this sends the
  place's coordinates and radius to Ticketmaster on every check.* The key
  lives encrypted on the source, like a linked account's credentials. The
  household-level `allow_cloud_models` toggle is not reused — it is about
  models, and a self-hoster who refuses cloud models might still accept a
  ticketing API, or the reverse — but the switch copies its posture:
  default off, argued for honestly, never silently on.
- **A provider's categories are data on the row, never the match.** The
  answer says "Music / Jazz"; that reaches the model's prompt as context
  beside the title, and nothing filters on it. §5.3's rule.
- **What is not coming**: Eventbrite retired public event search; Meetup's
  API is a paid tier; Songkick's is closed; Facebook events have no public
  interface at all. Each of those is reachable as an `ics` or `page` source
  where the organization publishes one — Meetup groups do, Eventbrite
  organizer pages carry JSON-LD — and the discovery recipes know it. The
  provider seam exists so that a new open API is one adapter; it is not a
  promise to keep chasing closed ones.

## 9. Waves

**W1 — places, sources, the river (no AI).** `Place`, `ListingSource`,
`Happening`; `Listings::Discover`, `::Parse::Ics` (over the extended
`Events::Import::Ics`), `::Parse::Schema`, `::Refresh`, the refresh jobs on
`recurring.yml`; `/places` with the help card; `/happenings` with Add to
calendar, Hide and the link; the hub's Near you card in its model-less form
(everything upcoming, by date); the source health tell. Every fetch through
`Web::Fetch`. *After W1 the whole thing is useful with no model: a merged,
polite, date-sorted view of every calendar you care about, one click from
your own.*

**W2 — the match.** `users.radar_brief` and its author; `Radar::Targets`,
`Radar::Match`, `HappeningMatch`, `MatchHappeningsJob`, the resweep; "Not
this" and Undo; the matched-only filter; the hobby chip and reason on rows;
`HobbiesLens#nearby`; the no-model line on every surface that would show a
match. Tests named for the promise: the no-model path, the injection path
(a happening titled with instructions files itself wrongly at worst), the
closed-set drop, once-per-series.

**W3 — the watcher.** `Watcher::EventRadar` in `Watcher::SLUGS`; the
`happening` action key in `Suggestion#materialize`, sharing one
event-from-happening path with the river's verb; `expires_on` and the three
`resolved?` cases; `Watcher::Base#dismissed` and the rejection it writes;
the per-place `alerts` switch and `lead_days`; the five-per-place cap.
Notification needs nothing — it is the D22 pipeline seeing a new watcher.

**W4 — trips.** Upcoming located stays as dated windows in both the match
and the watcher; the trip page's "While you're there" card and its paste box
prefilled with the destination; Travel as a second section on trip-window
suggestions and the events they create; the standing-place reuse when a stay
lands inside one.

**W5 — providers, and the wider set.** The `provider` kind and the
Ticketmaster adapter behind the opt-in switch; Education subjects as
targets; the Find-your-people / Find-a-class follow-up that ends in
`/places`; the about page (`about/features/_event_radar`, one row in
`About::Page::FEATURES`).

W2 needs W1; W3 needs W2; W4 and W5 need W3 and are independent of each
other. W1 alone is a shippable feature and should ship alone.

### 9.1 Files

| Concern | File |
|---|---|
| Places | `app/models/place.rb`, `app/controllers/places_controller.rb`, `app/views/places/` |
| Sources | `app/models/listing_source.rb`, `app/services/listings/{discover,refresh,parse/ics,parse/schema}.rb`, `app/jobs/refresh_listings_job.rb`, `app/jobs/refresh_listing_source_job.rb` |
| Parser extension | `app/services/events/import/ics.rb` (`uid`, `url`, `geo` on `ParsedEvent`; additive) |
| Happenings | `app/models/happening.rb`, `app/controllers/happenings_controller.rb`, `app/views/happenings/` |
| The match | `app/models/happening_match.rb`, `app/services/radar/{targets,match,brief}.rb`, `app/jobs/match_happenings_job.rb`, `users.radar_brief` |
| The watcher | `app/watchers/watcher/event_radar.rb`, `Watcher::SLUGS`, `Suggestion#materialize` (`happening` key), `Watcher::Base#dismissed` |
| Hub | `Sections::Panels::Hobbies#radar`, `Sections::Panels::HobbiesLens#nearby`, `sections/panels/_hobbies.html.erb`, `sections/_hobby_radar.html.erb` |
| Trips | `Radar::Windows` (standing places + located stays), `trips/show` "While you're there" |
| Providers | `app/services/listings/providers/ticketmaster.rb`, `ListingSource::PROVIDERS` |
| Schedule | `config/recurring.yml` (`refresh_listings`) |
| Tests | `test/services/listings/`, `test/services/radar/`, `test/watchers/event_radar_test.rb`, `test/controllers/{places,happenings}_controller_test.rb`, `test/models/happening_test.rb` |

## 10. Deliberately not doing (and what would change our minds)

- **Asking the model to find events.** Not on any model this app can assume,
  and a location leak on the ones that could. Revisit only under Q9, and
  even then as a *source* (the model's browsing as one more `provider` kind
  whose answer is validated into rows) — never as the feature.
- **Geocoding addresses.** No service, no model guessing. A happening is
  where its source is unless it carries a point. If enough sources turn out
  to publish addresses and no coordinates, the honest fix is a shipped
  dataset of venues, the way places shipped — not a lookup.
- **Reading prose pages for events.** A page without `Event` structured
  data is not a source. Scraping "Upcoming Shows" out of HTML is the
  keyword mistake wearing a different hat, and a page that wants to be
  found publishes the block.
- **RSS event feeds without structured dates.** An entry whose date lives
  only in its title is a story, and the reader already has it. If a dialect
  with real date fields (`xCal` in RSS, `ev:` namespaces) shows up in the
  wild often enough to matter, it is a parser, not a decision.
- **Scores, votes, "more like this".** The lesson of D-feed-reader, which
  is sharper for something that notifies: a correction is an example, the
  brief is the positive signal, and the model's sentence is the explanation.
- **Sharing places.** A place is private (Q14, D9). A household that wants
  "our town" shared by one member is asking for a household-level place
  whose *sources* are shared and whose matches stay per user — which is a
  `household_id` on `Place` and a `visible_to` OR-branch, cheap, and it
  should wait for a household to ask.
- **Auto-following anything.** Home is offered, the address is not
  resolved silently, and no starter list of calendars ships: a city's
  calendar is one URL per city, and a global list would be a promise to
  keep enumerating the world. The help card teaches where to look instead.
- **Provider-category matching.** Ticketmaster says "Jazz"; a keyword list
  someone else wrote is still a keyword list. It rides the prompt as
  context and decides nothing.
