<!-- decided -->
**D-event-radar. The model reads each new happening once against the user's hobbies and one owned sentence of interest; matches surface on the hub and hobby pages, and a watcher proposes the ones inside a place's lead time as suggestions that retire when the date passes — off, and said so, with no model**

"Would this person want to go to this?" is a judgment about an open subject,
so per D-no-keyword-logic the model answers it or nobody does: no
vocabulary, no provider category used as a shortcut, no score. The shape is
`Feeds::RouteStories`'s, which every classifier in the app shares. The
closed set (`Radar::Targets`) is every hobby lens with its per-user
`HobbyBrief` beside it, plus one **radar brief** (`users.radar_brief`) as
the target for everything that isn't a hobby — "two kids under six, farmers'
markets, free outdoor concerts, not bars" — prose the user owns, drafted by
the model from the hobby briefs and what the user has read, never
overwriting a sentence the user wrote (D-story-matching's rule, reused).
`Radar::Match` reads upcoming, in-range, unhidden happenings **once per
series**, oldest first, twenty a batch, capped at two hundred a run, in a
job; the answer per row is one target or leave it out plus one sentence of
why, validated against the set the run was given, written to every
occurrence in the series as a `HappeningMatch`. The arithmetic: three places
is on the order of a hundred new series a week, five calls; no places or no
model spends nothing. **Corrections are examples**: "Not this" tombstones
the match and returns the title in the next prompt as something the user
says is not that target, and dismissing the suggestion does the same through
a default-no-op `Watcher::Base#dismissed` hook, so both ways of saying no
teach the same lesson; there is no "more like this", because the positive
signal is the brief. Matches surface as a Near-you card on the Hobbies hub
and a `nearby` list on each hobby page (D37: panels, never the shared
files), and on `/happenings`, the date-sorted river with Add to calendar,
Not this, Hide and the link. `Watcher::EventRadar` (Hobbies dial) is SQL
over live matches inside the owning place's lead time, at most five per
place per scan and one per series, soonest first, fingerprint
`happening:<id>`, action `{ "happening" => id }` so a publisher's correction
reaches the click, `expires_on` the event's date, and `resolved?` opted in
for a rejected match, a hidden or cancelled row, or one the user already put
on the calendar themselves; accepting creates the `Event` through the same
path as the river's verb, tagged Hobbies and the matched lens (and Travel
inside a trip window). Notification is nothing new — Active sections'
proposals already leave through D22 with a decision link, and "Add to
calendar" is exactly the one-tap decision that link was built for. **With
no model configured** the listings still show, by date, and every surface
that would show a match carries one line saying nothing is matched and why;
no watcher runs. Design in `docs/EVENT_RADAR_PLAN.md` §5–§7. — *Not
started.*
