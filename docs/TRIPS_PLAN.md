# TRIPS_PLAN.md — trips as a travel management tool

`docs/TRAVEL.md` covers the Travel section's first life: the self-drawn photo
map and the trips detected in the library after the fact. This document is the
section's second life (**D-trip-spine**, **D-trip-companions**): trips as the
spine of a real travel-management tool — planned before you go, tracked while
it matters, shared with the household that's going too, and still the same
record the photos attach to when you're back.

The design brief came from the household actually using it: digital nomads in
a new Airbnb in a new state every two months. Their questions are concrete —
*where will we be in March; is the McCall place actually booked or did we just
talk about it; do we have somewhere to sleep on the drive between; is the
flight back for the wedding booked; do we have a car* — and every wave below
exists to answer one of them.

## 1. The shape: one Trip, two births

A `Trip` is still what D-travel-facet made it — a name, a date range, and (when
it has one) a box on the map. What changed is that the box is now optional
(all-or-none validated, only ever computed server-side from the owner's own
photos):

- **Found in photos** (unchanged): `Travel::Trips` proposes; keeping a
  candidate stores the recomputed box; photos and events derive from box +
  dates, so photos imported later join on their own.
- **Planned ahead** (new): a typed name, `place_label`, dates and description.
  No box, so no derived photos — `placed?` gates every coordinate-derived
  feature — and the page is an itinerary until you're back. When you *are*
  back, the detector will offer the same span as a found trip; keeping both
  is prevented by the overlap check, and deriving the box *into* the planned
  trip is Wave 2 work.

`phase` (upcoming / underway / past) is computed from the dates, never stored.

## 2. Stays and legs: the itinerary

Two children, both belonging to the **trip** (not a user — the itinerary is
collaborative, see §3), both carrying the single bit this whole tool exists to
track: `booking_status`, planned or booked.

- **`Stay`** — where you sleep. Location (free text — it's the label the hub
  and the calendar show), kind (Airbnb / hotel / vacation rental / friends &
  family / camping), check-in/check-out dates, listing URL, confirmation code,
  notes. Nights are **half-open**: a stay covers check-in up to but not
  including check-out, so checking out of Austin the morning you check into
  Denver leaves no phantom gap, and `Trip#lodging_gaps` can honestly list the
  nights nobody has covered.
- **`TripLeg`** — how you move. Kind (flight / drive / train / bus / ferry /
  car rental), date, optional return date (a rental's drop-off), optional
  departure time (flights), origin/destination, carrier, confirmation code.
  A **drive is bookless by default**: your own car needs no booking and the
  hub must never nag about it. The household that starts renting flips the
  leg to `car_rental` (or marks a drive planned) and the tracking switches
  back on — that toggle *is* the "maybe next year we rent" feature.

`Trip#timeline` merges both chronologically (legs before stays on a shared
day — you fly in before you check in) and is the trip page's lead card, each
row wearing its booked/not-booked chip.

## 3. Sharing: membership, and the Q14 line

**D-trip-companions**, in one sentence: a trip is shared by *membership*
(collaboration), not by AccessGrant (a read-only window), and nothing derived
from photo coordinates ever crosses users.

- `TripMembership` — household-checked companions; the owner is implicit.
  Companions see the trip everywhere (index, hub, calendar band), edit stays
  and legs, comment, and post photos. The owner alone edits the trip itself,
  manages the roster, and deletes; a companion can always leave.
- `TripComment` — the trip's shared thread ("host says park around back"),
  the app's first commentable surface. Author-or-owner delete.
- `TripPhoto` — **posting is the explicit act that shares a photo.** Each
  traveller's picker offers their own photos filtered by the trip's *dates*
  (never the box — a companion has no box, and the owner's box must not
  shape another user's picker). A posted photo reaches co-travellers through
  a `Photo.extra_visibility_clauses` OR-branch guarded like the album branch
  (poster must own the photo), and arrives EXIF-stripped like every shared
  variant.
- The trip **map** and derived **camera roll** stay owner-only on a shared
  trip — each traveller sees their own, nobody sees anybody else's. Q14 held,
  not widened. The per-album "share locations" toggle remains Q14's open
  half; a trip *choosing* to share its map would be that toggle's consumer.

## 4. The forward surfaces

- **`Travel::Outlook`** (the CareRadar idiom — computed fresh per request):
  the stay you're inside now, the next moves across every active trip in one
  chronological run, and the **warnings** — any stay or leg still planned
  (not booked) inside a 45-day booking lead, any run of uncovered nights
  inside the lead, any itinerary with no lodging at all. Two months out is a
  plan; six weeks out is a booking somebody needs to make.
- **The hub's "Where you'll be" card** renders the outlook: "You're in Boise
  through Jul 1", the Still-to-book callout (each line links into the trip's
  itinerary), the next-moves list. Below it, "Your trips" splits into
  upcoming rows (countdown, N-to-book chip) and the past grid of covers; the
  photo-candidate suggestions and the map are unchanged.
- **The calendar band**: each day covered by a stay on any trip you're on
  gets a thin sage strip under the day number — the place name printed on
  check-in day, Mondays and the 1st, the tint alone carrying the rest —
  linking to the trip. Check-out day inclusive here (you're physically there
  that morning) even though gap math is half-open; the two conventions serve
  different questions.
- **Events during a trip** still derive from dates alone (no link table, Q17
  stays deferred) — which is exactly how "the wedding we fly back for"
  surfaces on the trip page: it was on the calendar during the stay.

## 5. What's deliberately next (and not yet built)

Roughly in expected order of demand:

1. **The planned trip earns its box.** When a planned trip's dates have
   located photos ("Use my photos to place this trip"), derive the box the
   detector would have — the planned trip and the found trip become one
   record with one history. Until then the overlap check just keeps the
   detector from offering a duplicate.
2. **Stays on the map.** `Datasets::Places` can match a stay's location text
   by name (the same file, a name index instead of a band index), giving
   stays coordinates with zero network — a planned trip could draw its
   itinerary as pins on the same self-drawn basemap, and a route line
   between stays is the cross-country drive at a glance.
3. **Travel tools (Q9 Tier A).** A packing list from dates + destinations is
   honest (no live data); "find flights" is not. Renewal radar already keys
   off "renew"/"expir" for passports.
4. **Money as a lens, not a field.** Stays and legs deliberately carry no
   cost column yet; a trip's budget is Money-tagged items over the trip's
   dates — the lens the data model already gives us. Wait for a real want.
5. **A cross-trip "on the road" check** — lodging gaps *between* consecutive
   trips (the outlook currently checks within each trip). The nomad answer
   may simply be "make the drive its own short trip", so wait and see.
6. **Agent-mode watchers** (Milestone 3): the outlook's warnings are exactly
   what a `Watcher::BookingRadar` would surface as suggestions; the service
   is already viewer-scoped and date-parameterised for it.

## 6. Files

| Concern | File |
| --- | --- |
| Trip (spine) | `app/models/trip.rb`, `TripsController`, `app/views/trips/` |
| Stays | `app/models/stay.rb`, `StaysController`, `app/views/stays/` |
| Legs | `app/models/trip_leg.rb`, `TripLegsController`, `app/views/trip_legs/` |
| Companions | `app/models/trip_membership.rb`, `TripCompanionsController` |
| Comments | `app/models/trip_comment.rb`, `TripCommentsController` |
| Posted photos | `app/models/trip_photo.rb`, `TripPhotoPostsController`, the trip-post branch in `Photo.extra_visibility_clauses` |
| Outlook | `app/services/travel/outlook.rb` |
| Hub panel | `app/services/sections/panels/travel.rb`, `app/views/sections/panels/_travel.html.erb` |
| Calendar band | `CalendarController#show`, `app/views/calendar/show.html.erb` |
| Access rule | `app/controllers/concerns/trip_access.rb` |
| Tests | `test/models/trip_test.rb` (+ stay/leg/membership), `test/services/travel/outlook_test.rb`, `test/controllers/trip_planning_test.rb`, `trip_photo_posts_test.rb`, the band cases in `calendar_controller_test.rb`, the outlook cases in `travel_section_test.rb` |
