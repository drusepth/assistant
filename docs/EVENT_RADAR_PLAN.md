# EVENT_RADAR_PLAN.md — events near you, that you'd actually go to

`docs/HOBBIES.md` §3 asked for "find meetups nearby" and §4 for an **event
radar** — local happenings, releases, exhibits — and parked both behind Q9,
the open question about tools that need the live web. What shipped was the
honest half: `Tool::FindYourPeople` tells you where people who share a hobby
gather and forbids itself from naming a single real club, because the model
cannot browse. That is the right tool for a model that cannot see, and it is
not what the household asked for. The ask is: **tell me, ahead of time, about
events near the places I care about that I would likely want to go to, judged
by my hobbies and interests** — the library's programs and the city's
festivals, the volunteer shift at the food bank and the standing role at the
shelter, and the things I already said yes to on Meetup and Eventbrite.

This plan builds that without waiting on Q9, by the same move the reader made
(`docs/READER.md`, **D-feed-reader**): the app does not go looking for events;
the user points it at the calendars that publish them, the app polls those
politely, and the model — which cannot browse but can read — decides which of
the events it is holding are worth an interruption. Four decisions:

- **D-place-subscriptions** — a *place* is something you subscribe to: a
  named point from the gazetteer with a radius and a lead time, standing
  (home, the town you drive to on weekends) or dated (a stay on an upcoming
  trip). Coordinates come from the dataset the app already ships, never from
  a geocoding service.
- **D-listing-feeds** — events reach the app through *listing sources*
  attached to a place: iCalendar feeds, pages carrying schema.org `Event` or
  volunteer `JobPosting` data, and (later, opt-in) keyed provider APIs.
  "Near" is by construction — a source belongs to a place — and by
  arithmetic when an event carries its own coordinates. Nothing is geocoded,
  nothing is scraped from prose. What lands is a *happening*: a dated event
  or an undated *opening* (a volunteer role that is looking for people).
- **D-event-radar** — the model reads the happenings, batched and once each,
  against the closed set of the user's hobbies plus two sentences the user
  owns (interests, causes); matches surface on the hub and the hobby pages,
  and a watcher proposes the ones inside a place's lead time as suggestions
  that retire when the date passes. With no model configured, the listings
  still show, sorted by date, and the matching says it is off.
- **D-radar-accounts** — a linked Meetup or Eventbrite account contributes
  three different things and the app keeps them apart: what you've
  *committed to* (RSVPs, tickets) is calendar sync onto your own events;
  what you've *saved* is a happening the user already judged, which skips
  the model and goes straight to the lead-time nudge; and the *groups you
  belong to* are sources offered, never followed on your behalf.

## 1. What changes, in one paragraph

A new **Places** surface lets a user name the places whose events they want to
hear about — "Tulsa", "Grandma's town", the Lisbon stay in March — and, under
each, follow the calendars that publish what's on there: the city's events
feed, the library, the climbing gym's Meetup group, the volunteer center, the
venue whose page lists its shows. Those sources are polled on the reader's
politeness rules, and every event they publish lands as a **happening**: not
an Event on your calendar, but a candidate — dated, placed, linked — or, for
a volunteer role with no date, an *opening*. The Hobbies hub grows a "Near
you" card, the People hub a "Give time" card, and `/happenings` is the full
river, upcoming and by date, with "Add to calendar" and "Not this" on every
row. Behind it, once a model is configured, `Radar::Match` reads each new
happening against your hobbies, your one-line interest brief and your one-line
causes brief, and marks the ones it thinks are yours, with a sentence saying
why. `Watcher::EventRadar` then turns matches inside each place's lead time
into suggestions — the ordinary D20 kind, in Attend and on the Dashboard, and
on your phone if the section is set to Active — and each one retires the day
the event passes. Accepting puts the event on your calendar (or, for an
opening, a task to apply) tagged with what it matched. Dismissing tells the
matcher it was wrong. A linked Meetup or Eventbrite account adds the events
you already said yes to as calendar sync, the ones you saved as nudges that
need no judging, and your groups' calendars as sources one tick away.

## 2. Why sources, not search

The obvious build is the one HOBBIES.md deferred: ask the model for events
near the user. It fails three ways, and the failures are the reasons the
reader was built the way it was.

**The model cannot see.** Nothing in this app assumes the configured model
can browse (`docs/ROADMAP.md` → capability honesty), and the models this
project argues for — local ones — never will. A feature that only works on
one hosted provider's browsing mode is not a feature of this app.

**A search is a leak.** "Events near 36.15, -95.99 for someone into birding
and jazz who wants to volunteer with animals" is the household's location,
interests and values, sent to a third party, on a timer, forever. The app's
whole premise is that this stays home. Polling a public calendar the user
chose sends nothing about the user but the request itself, from a user agent
that says what it is.

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
and §4.5 is about it — an empty "paste a calendar URL" box is the RSS problem
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
Place        user_id, name, latitude, longitude (decimal 10,6), radius_mi (int, 25),
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
  Radius (default 25 miles) decides which of a source's events count as "here"
  when an event carries coordinates (§4.4). Lead time (default 14 days)
  decides how far ahead the watcher will interrupt you; the river shows
  further. There is no "importance" slider — the model's judgment plus the
  user's corrections is the whole ranking, and D-feed-reader's lesson about
  scores applies twice to something that will notify you.
- **Per user, never shared.** A place is a declared interest in a location,
  which is exactly the kind of thing D9 says stays private by default, and
  Q14 says coordinates never cross users. Two household members who both
  want Tulsa each add Tulsa; a source is one URL and the poll dedupes by URL
  across the household (§4.3), so the cost is one row, not one fetch.
  Sharing a place is in §11.
- **Home is offered, not assumed.** The Places page's empty state offers
  "Add where you live" prefilled from the last line of the household address
  (`households.address` → gazetteer), and the user confirms it. The address
  is free text a human typed for letters; resolving it silently and polling
  on the strength of the guess is the wrong kind of helpful.
- **A trip's stay is a dated place.** Wave 5 (§10) makes each upcoming `Stay`
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
- **`page`** — a web page carrying schema.org structured data (JSON-LD, the
  form Google's event search requires, so publishers keep it correct).
  `Listings::Parse::Schema` walks every `<script type="application/ld+json">`
  block and reads two shapes: objects whose `@type` is `Event` or a subtype
  (`name`, `startDate`, `endDate`, `url`, `location.name`,
  `location.address`, `location.geo`, `eventStatus` — cancelled and
  postponed are honored — and `@id`/`url` as the uid), and objects whose
  `@type` is `JobPosting` with `employmentType` `VOLUNTEER` (§4.6). A venue's
  "upcoming shows" page, a Meetup group's events page, an Eventbrite
  organizer page and a nonprofit's "volunteer with us" page are each one
  source this way. Parsing structured data is deterministic, so it is on the
  right side of **D-no-keyword-logic**: the page's *prose* is never read for
  dates, names or roles, only the block the publisher wrote for machines.
- **`provider`** — a keyed API queried by the place's point and radius
  (§8). Same table, same politeness, same happenings; the difference is what
  the URL is and the fact that the request names a location.

Everything above `Listings::Refresh` is kind-blind: a source yields a list of
parsed happenings, and the ingest is the same.

### 4.2 Discovery: paste anything

`Listings::Discover` is `Feeds::Discover` for calendars, and the recipes are
the feature, because nobody knows their library's iCal URL by heart:

- a `.ics`/`webcal:` URL, or a body starting `BEGIN:VCALENDAR`, is an `ics`
  source as-is;
- a page is fetched once (`Web::Fetch.raw`, size-capped, SSRF-guarded) and,
  in order: `<link rel="alternate" type="text/calendar">` wins as `ics`;
  otherwise any `Event` or volunteer `JobPosting` JSON-LD on the page makes
  it a `page` source; otherwise the conventional paths (`/calendar.ics`,
  `/events.ics`, `/events/ical`, `/?ical=1` — Localist, Trumba, The Events
  Calendar, CivicPlus and LibCal between them cover most cities, campuses
  and libraries) are tried, capped like the reader's guesses;
- **known hosts are rewritten**, the way the reader rewrites a subreddit to
  its RSS: a Meetup group URL becomes that group's iCal export, a public
  Google Calendar embed becomes its `.ics`, an Eventbrite organizer page is
  kept as a `page` source. (LibCal's per-calendar iCal link is what the
  paste box wants; the page itself carries no rewrite rule.)
  The table is small, hand-maintained and tested, and it is a URL rewrite,
  not a classification.

Nothing found → the form says what it tried and what a calendar link looks
like, and offers the per-place help card (§4.5) instead of a dead end.

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
Happening   listing_source_id, kind (event | opening), provenance (listed | saved),
            uid, series_uid, title, description (text, plain), location, url,
            latitude, longitude, starts_at (nullable for openings), ends_at, all_day,
            expires_on, last_seen_at, distance_mi, out_of_range (bool),
            event_id (nullable), task_id (nullable), hidden_at, matched_at
```

A happening is **not an `Event`**. The calendar is the user's own life, and
D-feed-reader's line about stories applies: nothing lands on it without a
click. So happenings have their own table and their own verbs, and an
`Event` is created from one only by "Add to calendar" or by accepting a
suggestion — at which point `event_id` links them, so the row can say "on
your calendar" and the watcher can tell handled from ignored. An opening
links a `task_id` the same way (§4.6).

- **Idempotent by `uid`**, like feed items by guid: a re-listed happening
  keeps its matches, its hidden state and its link to the event you made.
  A recurring rule yields one happening per occurrence, each with the
  master's `series_uid`, and §5 uses that so a weekly meetup is judged once,
  not fifty-two times. `last_seen_at` is stamped on every refresh that still
  lists the row; a row a source stopped listing is *withdrawn*, which
  matters most for openings.
- **Near is by construction, then by arithmetic.** A happening from a source
  attached to Tulsa is *in Tulsa* unless it says otherwise. When it carries
  coordinates (iCal `GEO`, JSON-LD `location.geo` or `jobLocation`'s geo, a
  provider's venue) the haversine `Datasets::Places` already has gives
  `distance_mi`, and a row outside the place's radius is kept but marked
  `out_of_range` — hidden from the river and never matched, visible under a
  fold on the source's page so a wrong radius is diagnosable. An address
  string is *never* turned into a point: no geocoder, and no model guessing
  coordinates from "Cain's Ballroom" (**D-travel-facet**'s "confidently
  wrong Paris" rule).
- **Past is pruned.** An event whose end passed more than 30 days ago, or an
  opening withdrawn or expired more than 30 days ago, is deleted unless it
  is linked to an event or task; the radar is not an archive, and the
  calendar and the board keep what you kept. Matches go with it.
- **Hostile input, handled where the reader handles it.** Titles, locations
  and descriptions are stripped to plain text at parse time (`Nokogiri` text
  for anything HTML-shaped, entity expansion off, `nonet`), URLs are refused
  unless `http(s)` in the parser, `uid` is truncated, and nothing downstream
  holds a string it could be tempted to mark safe. A stranger's calendar can
  put words in a row; it cannot put markup on the page or a request in the
  app.

### 4.5 Where calendars hide: libraries and the institutions people mean

"Events near me" in practice means a short list of institutions, and most of
them publish a feed they never advertise. The per-place help card is a list
of those institutions, each with what to look for and a **Find it** link —
and the Find it link is honest about what it is: it opens a web search in the
*user's browser* for `"<place> public library events calendar"`, so the app
sends nothing and looks nothing up, and the person lands on the page the
paste box can read.

- **The library.** The three platforms behind most North American
  public-library calendars — LibCal, Communico and BiblioCommons — each
  publish iCal per calendar or per branch, and LibCal also publishes RSS.
  The discovery rewrite for LibCal hosts means pasting the events page is
  enough; the card says "look for *Subscribe* or the calendar icon" for the
  rest. Story times, author talks, maker-space hours, tax-help clinics,
  seed libraries: the library is the single richest free calendar in any
  town, which is why it is first.
- **The city and the county.** Parks and recreation, the civic calendar,
  the farmers' market, the public-works "what's closed" feed. Usually
  CivicPlus, Localist or Trumba, all with iCal.
- **The university and the community college.** Localist almost
  everywhere: lectures, recitals, games, continuing-ed open houses.
- **Museums, theatres, venues, the zoo.** Their own "upcoming" page,
  which nearly always carries `Event` JSON-LD because they want Google to
  list them.
- **Meetup groups.** Every group has an iCal export; paste the group's
  address and the rewrite finds it. A linked Meetup account offers your
  groups' calendars without the paste (§9).
- **Places of worship, clubs, leagues.** Most are a Google Calendar
  embedded on a page, and a public Google Calendar has an `.ics` the
  rewrite knows.
- **The volunteer center** (§4.6) — the United Way, the community
  foundation, the city's volunteer office, the food bank, the shelter.

Two rules from HOBBIES_HUB_PLAN §7.1 hold here: **offered, never
subscribed** (nothing is followed because the card listed it), and **no
global starter list** — a city's calendar is one URL per city, and a list
that tried to hold them all would be a promise to keep enumerating the world.
The card teaches where to look; the rewrites make the looking short.

### 4.6 Volunteering: openings as well as events

A volunteer opportunity comes in two shapes, and only one of them is an
event. The park cleanup on Saturday is a happening like any other — dated,
placed, from the volunteer center's calendar or the nonprofit's events page.
"Weekend dog walkers wanted" has no date: it is a **role that is looking for
people**, open until it isn't. The radar holds both, and the second is an
**opening**: `kind: opening`, no `starts_at`, `expires_on` when the posting
says (`JobPosting.validThrough`), withdrawn when its source stops listing it.

- **Where they come from.** The `page` parser's second shape: schema.org
  `JobPosting` with `employmentType` `VOLUNTEER`, which is the documented
  way to mark a volunteer role and what Idealist-style boards and many
  nonprofit sites publish (`title`, `description`, `hiringOrganization`,
  `jobLocation` with address and geo, `validThrough`, `url`). Plus any
  volunteer center's calendar as an `ics` source for the dated kind. The
  large volunteer platforms — VolunteerMatch, Idealist — gate their APIs
  behind partner agreements; JustServe and the local centers that run on
  Galaxy Digital's Get Connected publish public pages; where a page carries
  the JSON-LD the parser reads it, where a platform offers a public feed or
  an open keyed API it is one row in the rewrite table or one adapter under
  §8, and where it offers neither the card says so rather than scraping
  prose (§11).
- **Where they show.** Openings and volunteer events surface on the
  **People** hub — communities, church, clubs, the section whose whole
  premise is showing up (`docs/PEOPLE.md`'s recurring-venue rule, which
  `Tool::MakeNewFriends` already argues) — as a **Give time** card, and on
  `/happenings` under an "Openings" filter, listed by when they were first
  seen rather than by a date they don't have.
- **How they're judged.** Against the **causes brief** (§5.1): one sentence
  saying what the person would give time to. The question "would you
  volunteer for this?" is the same open-subject judgment as "would you go
  to this?", asked of a different sentence.
- **What accepting does.** An opening has nothing to put on a calendar, so
  its verb is **Make a task** — "Apply: weekend dog walker at Tulsa SPCA",
  notes carrying the link and the organization, tagged People and, for a
  cause that is also a hobby (the trail crew, the birding census), the
  lens. The board is where "I should look into that" goes to become "I
  did", which is the point of the Tasks section.
- **How they're nudged.** An opening has no lead time to wait for, so the
  watcher proposes a matched opening *once*, when it is first seen, and the
  suggestion retires when the row is withdrawn or expires or a task exists
  for it. The same five-per-place cap applies across both kinds.

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
- **one interest brief** (`users.radar_brief`, ≤ 600 chars) as the target
  `household`: the sentence for everything that isn't a hobby. "Two kids
  under six, we like farmers' markets, free outdoor concerts and anything at
  the science museum; not bars, not late nights."
- **one causes brief** (`users.causes_brief`, ≤ 600 chars) as the target
  `causes`: what the person would give time to. "Animals, food security,
  anything outdoors with a shovel; weekends only; not phone banking." Kept
  separate from the interest brief because it answers a different question
  (§4.6) and because a household member who wants the events and not the
  asks can leave it blank, which turns volunteering off for them.

Both briefs are prose the user owns, the same way a hobby brief is — nothing
compares them to anything, so they can't be wrong the way a rule can. The
model drafts each from the hobby briefs, what the user has read in the
reader and, when an account is linked, the events they have saved or
attended (§9); a sentence the user wrote is never overwritten
(`Feeds::Briefs::Author`'s rule, reused).

The answer per happening is *one target or leave it out*, plus one sentence
of why. Leaving it out is the right answer for most rows, and the prompt says
so; the arithmetic in §5.3 depends on it.

Wave 7 widens the set with active **Education subjects** (`subjects.title` +
`interest_frame`), so a planetarium talk reaches a kid's astronomy course —
another lens dividend, and a prompt change plus one more branch in
`Targets`, not a schema change.

### 5.2 One question per series, once

`Radar::Match` takes the user's unmatched happenings that are upcoming (or,
for openings, live), in range, not hidden and `provenance: listed` — **one
per `series_uid`**, oldest first — in batches of twenty, with title, first
300 characters of description, venue or organization, the place's name and
the date, and writes the answer to every occurrence in the series.
`matched_at` is stamped whether or not anything matched, so a row is read
once; a new hobby, a changed brief or a "Not this" clears it for a bounded
resweep (the last 30 days of arrivals, capped), the way
`Feeds::RouteStories.resweep!` does. The cap per run is 200 rows — ten
calls — and a run only ever happens in a job with `RetriesModelCalls`.

```
HappeningMatch   happening_id, target (string: "section:12" | "household" | "causes"),
                 section_id (nullable), reason (≤ 200), source (model | hand), rejected_at
```

Unique on `(happening_id, target)`. `section_id` is denormalized from the
target for the joins the hobby pages make; `target` is the closed-set key
the model actually chose, and a key that isn't in the set the run was given
is dropped before anything is written.

### 5.3 The arithmetic, honestly

A place with four sources — a city calendar, a library, a Meetup group and a
venue — publishes on the order of 40–120 upcoming happenings at any time,
and gains maybe 20–40 new series a week; a volunteer center adds a handful
of openings a week. Three places is ~100 new rows a week, five batches, five
model calls. A household with no places spends nothing; a household with no
model spends nothing and is told so. This is the "ask about less" route to
affordability: new series only, once each, inside the radius, never the
occurrences, and never the rows the user already judged (§9).

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
is the brief, which the user can edit in a sentence — and, once an account
is linked, the events they actually saved and went to, which are better
examples than any vote (§9).

### 5.5 With no model configured

Sources poll, happenings land, the river shows everything by date, "Add to
calendar" and "Make a task" work, and every surface that would show a match
shows one line instead: *No model is configured, so nothing here is matched
to your hobbies — everything near each place is listed by date.* No watcher
runs for listed rows (a suggestion with no judgment behind it is a
newsletter) — except for **saved** rows from a linked account, which carry
the user's own judgment and are nudged regardless (§9). That is the same
reduction the reader accepted, and for the same reason: an honest list beats
a plausible guess, and a local model does this job for free.

## 6. Surfaces

### 6.1 The hub cards and the hobby pages

`Sections::Panels::Hobbies` gains a memoized `radar` (batched across places,
never per card, like `rows`) and `_hobbies.html.erb` renders one **Near
you** card after the hobby grid: the next few matched happenings across all
places, date-first, each with its hobby chip and the model's sentence on
hover, and "See what's on →" to `/happenings`. A household with no places
gets a one-line doorway to Places instead of a card.

`Sections::Panels::People` gains `openings` and `_people.html.erb` renders a
**Give time** card: matched openings and volunteer events, organization-first,
with "Make a task" on each. A user with no causes brief and no volunteer
sources sees nothing here, not an empty card.

`Sections::Panels::HobbiesLens` gains `nearby`: matched happenings for
*this* hobby, upcoming, with the same verbs — the "Birding, near you" list
the whole feature exists to produce, on the page where someone has already
decided to spend time on birding.

Nothing in `SectionsController`, `sections/show.html.erb` or `SectionsHelper`
changes (D37).

### 6.2 `/happenings`, the river

The everything-view, in the reader's density: upcoming, by date, grouped by
day, filtered by place, by hobby (matches only), by source, or to openings
only; "matched only" is on by default when a model is configured and absent
when it isn't. Each row: date and time (or "open since" for an opening),
title, venue or organization and distance when known, the place chip, the
target chip and its reason, a "saved on Meetup" tell where it applies, and
the verbs:

- **Add to calendar** — creates the `Event` from the row (title, start, end,
  all-day, location, description with the link), tagged Hobbies and the
  matched lens (and Travel inside a trip window), links `event_id`, and the
  row shows "on your calendar". A direct write on a click, like "Make a
  task" in the reader.
- **Make a task** — the opening's verb (§4.6); also offered on events for
  "get tickets" without committing the calendar.
- **Not this** — §5.4. Undo restores.
- **Hide** — for the thing you're simply not going to; no lesson taught.
- the link out, `rel="noopener noreferrer nofollow"`.

Turbo replaces the row on each verb, the reader's `act` pattern, HTML
fallback redirects to the river.

### 6.3 Places

`/places`: the user's places as cards — name, radius, lead time, alert
switch, the sources under it with the reader's health tell (green, backing
off, failing since), what's on next — and, per place, the paste box and the
**where calendars hide** card (§4.5) with its Find it links. Linked accounts
(§9) add an **Your groups** shelf under each place: the Meetup groups you
belong to whose calendars aren't followed yet, one tick each.

`Tool::FindYourPeople` and the planned "Find a class" learn one new
follow-up shape: *follow the listings* — when the draft names a kind of
organization, its check-this-week task links to `/places` with the place
prefilled. This is HOBBIES.md's "upgrades in place when Q9 resolves" landing
without Q9: the tool still never names a real club, but the user who finds
one now has somewhere to point it.

### 6.4 Settings

Two dials govern the watcher, as they govern everything under their
sections: **Hobbies** for events (*Off* → no suggestions; *Quiet* → weekly,
in-app; *Active* → daily, and the phone hears about it — §7.1) and
**People** for openings and volunteer events. Per place, `alerts` turns the
watcher off for that place without unfollowing anything (the town you visit
twice a year is worth a river, not a nudge), and `lead_days` sets how far
ahead. Both briefs are edited on `/places` and on the hobby brief card, with
the same "draft one for me" button and the same rule that a written one
wins.

## 7. The watcher (D-event-radar, continued)

`Watcher::EventRadar` (`section_slugs: %w[hobbies people]` — the loudest
dial wins, per `AgentScanJob.dial_for`, so a household that turned People up
for its circle hears about openings daily and about concerts weekly) is SQL
over `happening_matches` plus saved rows: live matches whose happening
starts inside the owning place's `lead_days` (or, for an opening, is newly
seen), is in range, not hidden, not linked to an event or task, and whose
suggestion doesn't exist yet. It proposes at most **five per place per
scan**, soonest first, and never more than one per series (the Tuesday walk
is one suggestion, expiring and re-proposable per occurrence bucket, not
one per Tuesday).

- **Fingerprint** `happening:<id>` — the subject is a row, so
  `subject_id` works and nothing re-proposes a dismissed one.
- **Title** is date-first — *Sat 3 Oct · Fall Bird Walk, Lakeside Park
  (Birding, 6 mi)* — because a date is a commitment and a name is a pile;
  an opening is organization-first — *Tulsa SPCA is looking for weekend dog
  walkers (Causes)*. **Body** is the model's sentence, the venue and the
  time, or for a saved row, *you saved this on Meetup*.
- **Action** `{ "happening" => id, "expires_on" => date, "accept_label" =>
  "Add to calendar" | "Make a task" }`. `Suggestion#materialize` learns the
  `happening` key and creates the `Event` (or, for an opening, the `Task`)
  from the row exactly as the river's verb does — one path, so the calendar
  event is identical whichever way it arrived. The payload carries an id
  rather than a copy of the fields, so a publisher's correction (new time,
  cancelled, withdrawn) reaches the click.
- **Retires** on `expires_on` for free (**D-suggestion-lifecycle**), and
  `resolved?` opts in for three more: the match was rejected, the happening
  was hidden, cancelled or withdrawn, or the row is now linked to an event
  or task — you added it yourself from the river, and a nudge about a thing
  on your calendar is the D-reminders failure restated.
- **Sections on the suggestion** are what it matched: Hobbies and the lens
  for a hobby target; Hobbies for `household`; People for `causes`; Travel
  added inside a trip window. The created event or task inherits them.
- **Trip windows** (Wave 5): for each upcoming located `Stay` on a trip the
  user is on, the same query runs with the stay's point, the trip's radius
  (25 miles, the place default) and the stay's dates as both window and lead —
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
  interface at all (the `facebook` entry in `LinkedAccount::PROVIDERS`
  declares an events scope that nothing can sync, and the card should say
  so rather than imply it). Each of those is reachable as an `ics` or
  `page` source where the organization publishes one — Meetup groups do,
  Eventbrite organizer pages carry JSON-LD — and the discovery recipes know
  it. The provider seam exists so that a new open API is one adapter; it is
  not a promise to keep chasing closed ones.

## 9. Your own accounts: Meetup and Eventbrite (D-radar-accounts)

Everything above is about strangers' calendars. Your Meetup and Eventbrite
accounts hold something different — **what you already said about
yourself**: the events you RSVP'd to or bought tickets for, the ones you
saved to think about, the groups you joined. The plan reads those through
the linked-account registry (**D26**: one entry in
`LinkedAccount::PROVIDERS`, credentials encrypted, scope-gated with
`allows?`, synced by `SyncLinkedAccountJob`) and — this is the decision —
keeps the three kinds apart, because they mean three different things:

- **Committed is calendar sync.** An RSVP or a ticket is already your event;
  it belongs on your calendar the way a CalDAV event does, not in a river of
  candidates. `Meetup::CalendarSync` and `Eventbrite::OrdersSync` ride
  `Events::Import` exactly as `Events::CaldavSync` does — same dedupe, same
  window, read-only — and the events land tagged Hobbies, then auto-sorted
  into a lens by `CategorizeEventJob` like any other event. Meetup exposes
  this as a personal iCal export of your upcoming events (a private URL the
  user pastes as the account's credential); Eventbrite as `/users/me/orders/`
  on a personal API token from the account's developer settings.
- **Saved is a happening you already judged.** A saved or "interested"
  event is exactly the row the matcher exists to find, found by the person
  instead: it lands as a happening with `provenance: saved`, skips
  `Radar::Match` (§5.2 never reads it — the user's judgment is not a
  question for the model), shows a "saved on Meetup" tell in the river, and
  is nudged by the watcher inside the lead time like any match — *with or
  without a model*, since no judgment is being borrowed. Meetup's saved
  events and Eventbrite's likes are exposed unevenly (Eventbrite's v3 API
  documents orders but not likes as of this writing; Meetup's saved list
  needs the GraphQL API behind an OAuth client) — so this lands where the
  platform exposes it and the account card says which, rather than
  promising both.
- **Your groups are offered sources.** The groups you belong to each have a
  calendar; the account puts them on the **Your groups** shelf under each
  place (§6.3), one tick each, matched to a place by nothing cleverer than
  the user's tick. HOBBIES_HUB_PLAN §7.1's rule holds: offered, never
  subscribed — joining a group on Meetup does not make the app follow it.
- **Attended and saved are the best examples the briefs can have.** The
  brief authors (§5.1) read the titles of events you went to and saved,
  the way `Feeds::Briefs::Author` reads the stories you opened: a
  subscription says you were curious once, an RSVP says you got in the car.
  They ride the prompt as examples of what *this* person picks; they are
  never turned into a rule, a vocabulary or a score.

What the account never does: post, RSVP, save or join on your behalf
(read-only scopes, the D26 posture, and Q19's consent design is still
unbuilt); share anything with other household members; or feed the
provider anything about the places you follow — the sync reads the account,
it does not query the platform with your radius.

## 10. Waves

All seven are built (2026-09). What the building changed is at the end of
this section.

**W1 ✅ — places, sources, the river (no AI).** `Place`, `ListingSource`,
`Happening`; `Listings::Discover` with the rewrite table (Meetup groups,
Google Calendar embeds, LibCal), `::Parse::Ics` (over the extended
`Events::Import::Ics`), `::Parse::Schema` for `Event` JSON-LD, `::Refresh`,
the refresh jobs on `recurring.yml`; `/places` with the where-calendars-hide
card and its Find it links; `/happenings` with Add to calendar, Make a task,
Hide and the link; the hub's Near you card in its model-less form
(everything upcoming, by date); the source health tell. Every fetch through
`Web::Fetch`. *After W1 the whole thing is useful with no model: a merged,
polite, date-sorted view of every calendar you care about — the library's,
the city's, the venue's — one click from your own.*

**W2 ✅ — the match.** `users.radar_brief`, `users.causes_brief` and their
author; `Radar::Targets`, `Radar::Match`, `HappeningMatch`,
`MatchHappeningsJob`, the resweep; "Not this" and Undo; the matched-only
filter; the target chip and reason on rows; `HobbiesLens#nearby`; the
no-model line on every surface that would show a match. Tests named for the
promise: the no-model path, the injection path (a happening titled with
instructions files itself wrongly at worst), the closed-set drop,
once-per-series.

**W3 ✅ — the watcher.** `Watcher::EventRadar` in `Watcher::SLUGS`; the
`happening` action key in `Suggestion#materialize`, sharing one
event-from-happening path with the river's verb; `expires_on` and the
`resolved?` cases; `Watcher::Base#dismissed` and the rejection it writes;
the per-place `alerts` switch and `lead_days`; the five-per-place cap.
Notification needs nothing — it is the D22 pipeline seeing a new watcher.

**W4 ✅ — openings.** The `JobPosting` shape in `Parse::Schema`; `kind`,
`expires_on`, `last_seen_at` and withdrawal on `Happening`; the task path in
the river verb and in `materialize`; `Panels::People#openings` and the Give
time card; the Openings filter; the People dial on the watcher and the
once-when-seen rule; the volunteer-center row on the help card.

**W5 ✅ — trips.** Upcoming located stays as dated windows in both the match
and the watcher; the trip page's "While you're there" card and its paste box
prefilled with the destination; Travel as a second section on trip-window
suggestions and the events they create; the standing-place reuse when a stay
lands inside one.

**W6 ✅ — your accounts.** `meetup` and `eventbrite` in
`LinkedAccount::PROVIDERS` with read-only scopes; `Meetup::CalendarSync` and
`Eventbrite::OrdersSync` over `Events::Import`; `provenance: saved` rows and
their no-model nudge; the Your groups shelf; attended and saved titles in
the brief authors. Whichever of saved-events and likes a platform exposes,
with the card saying which.

**W7 ✅ — providers, and the wider set.** The `provider` kind and the
Ticketmaster adapter behind the opt-in switch; Education subjects as
targets; the Find-your-people / Find-a-class follow-up that ends in
`/places`; the about page (`about/features/_event_radar`, one row in
`About::Page::FEATURES`).

W2 needs W1; W3 needs W2; W4 needs W3 (it is a second kind through the same
match and watcher); W5, W6 and W7 need W3 and are independent of each
other. W1 alone is a shippable feature and should ship alone.

Five things the build changed. **A trip window is a place, not a row.**
The design said a stay is "a dated place with no Place row", but a source
belongs to a place, so a stay with nothing followed for it has nothing to
read; `Radar::Windows` therefore matches each located stay against the
user's *own* places and uses the stay's nights as that place's window, and
the trip page offers a stay with no place nearby as one click to add. **A
"maybe" is the saved row.** Neither platform exposes likes, so `provenance:
saved` is fed by the one thing the Meetup export does say: `STATUS:TENTATIVE`
on an RSVP — the user's own "maybe", which is exactly the judgment the row
was meant to carry. The groups are typed on the account rather than read
from an API. **Saved rows need a place too**, and land under the user's
place whose radius covers them, else the first, else nowhere. **The
volunteer parser landed in W1**, since it is one more branch of the same
JSON-LD walk; W4 added the surfaces. **An `account` source kind** exists so
the account sync's rows have a home the river already knows how to read,
and it is never in the sweep. The about page ships without a screenshot
until the demo household has a place to photograph.

### 10.1 Files

| Concern | File |
|---|---|
| Places | `app/models/place.rb`, `app/controllers/places_controller.rb`, `app/views/places/` (incl. `_where_calendars_hide.html.erb`) |
| Sources | `app/models/listing_source.rb`, `app/services/listings/{discover,refresh,parse/ics,parse/schema}.rb`, `app/jobs/refresh_listings_job.rb`, `app/jobs/refresh_listing_source_job.rb` |
| Parser extension | `app/services/events/import/ics.rb` (`uid`, `url`, `geo` on `ParsedEvent`; additive) |
| Happenings | `app/models/happening.rb`, `app/controllers/happenings_controller.rb`, `app/views/happenings/` |
| The match | `app/models/happening_match.rb`, `app/services/radar/{targets,match,briefs}.rb`, `app/jobs/match_happenings_job.rb`, `users.radar_brief`, `users.causes_brief` |
| The watcher | `app/watchers/watcher/event_radar.rb`, `Watcher::SLUGS`, `Suggestion#materialize` (`happening` key), `Watcher::Base#dismissed` |
| Hubs | `Sections::Panels::Hobbies#radar`, `Sections::Panels::People#openings`, `Sections::Panels::HobbiesLens#nearby`, `sections/panels/_hobbies.html.erb`, `sections/panels/_people.html.erb`, `sections/_hobby_radar.html.erb`, `sections/_give_time.html.erb` |
| Trips | `Radar::Windows` (standing places + located stays), `trips/show` "While you're there" |
| Accounts | `LinkedAccount::PROVIDERS` (`meetup`, `eventbrite`), `app/services/meetup/calendar_sync.rb`, `app/services/eventbrite/orders_sync.rb`, `app/services/radar/saved.rb` |
| Providers | `app/services/listings/providers/ticketmaster.rb`, `ListingSource::PROVIDERS` |
| Schedule | `config/recurring.yml` (`refresh_listings`) |
| Tests | `test/services/listings/`, `test/services/radar/`, `test/watchers/event_radar_test.rb`, `test/controllers/{places,happenings}_controller_test.rb`, `test/models/happening_test.rb`, `test/services/{meetup,eventbrite}/` |

## 11. Deliberately not doing (and what would change our minds)

- **Asking the model to find events.** Not on any model this app can assume,
  and a location leak on the ones that could. Revisit only under Q9, and
  even then as a *source* (the model's browsing as one more `provider` kind
  whose answer is validated into rows) — never as the feature.
- **Geocoding addresses.** No service, no model guessing. A happening is
  where its source is unless it carries a point. If enough sources turn out
  to publish addresses and no coordinates, the honest fix is a shipped
  dataset of venues, the way places shipped — not a lookup.
- **Reading prose pages for events or roles.** A page without `Event` or
  `JobPosting` structured data is not a source. Scraping "Upcoming Shows"
  or "Ways to help" out of HTML is the keyword mistake wearing a different
  hat, and a page that wants to be found publishes the block. This is also
  why VolunteerMatch's search pages are not a source: the honest route to a
  gated platform is its API, by application, as one adapter.
- **RSS event feeds without structured dates.** An entry whose date lives
  only in its title is a story, and the reader already has it. If a dialect
  with real date fields (`xCal` in RSS, `ev:` namespaces) shows up in the
  wild often enough to matter, it is a parser, not a decision.
- **Scores, votes, "more like this".** The lesson of D-feed-reader, which
  is sharper for something that notifies: a correction is an example, the
  brief is the positive signal, the events you actually went to are the
  best examples of all, and the model's sentence is the explanation.
- **Acting on your accounts.** No RSVP, save, join or post through a linked
  account; read-only until Q19's consent design exists, and then only as
  its own decision.
- **Sharing places.** A place is private (Q14, D9). A household that wants
  "our town" shared by one member is asking for a household-level place
  whose *sources* are shared and whose matches stay per user — which is a
  `household_id` on `Place` and a `visible_to` OR-branch, cheap, and it
  should wait for a household to ask.
- **Auto-following anything.** Home is offered, the address is not
  resolved silently, your Meetup groups are a shelf and not a subscription,
  and no starter list of calendars ships: a city's calendar is one URL per
  city, and a global list would be a promise to keep enumerating the world.
  The help card teaches where to look instead.
- **Provider-category matching.** Ticketmaster says "Jazz"; a keyword list
  someone else wrote is still a keyword list. It rides the prompt as
  context and decides nothing.
