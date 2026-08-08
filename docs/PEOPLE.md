# PEOPLE.md

Section deep-dive for **People** — what the section page *is*, now that the
Address Book exists, and how the section earns its place across all three
modes (D6). Everything rides existing infrastructure (D18 anatomy, D19 tools,
D25 lenses, D28 routing, D29 chat) except where flagged. The one decision it
needs — the roster/dashboard split — is **D38** in `DECISIONS.md`;
person↔item linking is logged as open question **Q14**. (Numbers provisional
per the merge-time renumbering rule in `CLAUDE.md`.) The first build pass —
steps 1–6 of §9 — is built, marked ✅ below.

## Why this section matters (mission tie)

People is the *connection* section, and connection is where the target user is
bleeding worst. The wealthy have always had social infrastructure: assistants
who remember every birthday and send the gift, clubs that manufacture
friendship, planners who make the gathering happen. The 99% get a contacts app
that is a graveyard and a feed engineered to substitute scrolling *about*
people for time *with* them. The counter-move is the standard one: owned
context + tools that end in contact — a message sent, a plan on the calendar,
a visit logged — never in a better-groomed database.

That names the design trap up front: **CRM-ification**. Salesforce-for-friends
treats people as pipeline; the moment the section's core loop is "enrich the
contact record," we've built the wrong thing. D16 discipline applies double
(same trap Hobbies dodged with tracking): capture stays near-zero, and every
feature should end in reaching out, showing up, or planning something — not in
maintaining records. And per PRODUCT.md's atomization line, the section must
eventually serve *groups* (church, clubs, mutual aid), not just dyads — an
assistant that only optimizes individual friendships recreates the problem.

## 1. The identity question: section page vs. Address Book (D38)

Today the People section page is the generic D18 lens, and its Browse zone
renders a grid of Person cards — a duplicate of the Address Book. Worse than
redundant: after a CardDAV sync it becomes three hundred acquaintances,
and the roster drowns the relationships.

The Documents precedent already settled this pattern — vault = the storage
surface (everything, import, filters), section page = the section's working
slice. Same split here, sharpened, because People has *three* surfaces:

| Surface | Job | CRM-ness |
|---|---|---|
| **Address Book** (`/people`) | The roster: everyone, import/sync, add/edit | All of it |
| **Person page** (`people#show`) | One relationship: profile, notes, log contact, Reconnect | Per-person |
| **People section page** | The social dashboard: who's drifting, what's coming up, tools | None |

**D38**: the section page stops listing Person rows entirely. A one-line
"N people in your Address Book →" link replaces the grid. The page is about
the *state of your relationships*, not the existence of contacts — the
lens model's real dividend here is that the People lens still holds Events,
Tasks, Notes, and Goals ("dinner with Sam", "call the landlord about the
deposit — no wait, that's Rights", "make friends in the new city"), and
*those* are what the Browse zone is for.

## 2. Foundation: the circle, not the rolodex

Every module below needs an answer to "who do you actually mean" — an import
must not turn 300 contacts into 300 obligations. Q8 already found the
principle: **explicit and manual beats inferred**, because a wrong "call your
mom" costs trust the app never earns back.

- **`people.keep_in_touch`** (boolean, default false) — the circle flag. Set
  from the person page and from the section page's capture card. The flag is
  intent ("this relationship is one I'm tending"); it creates no obligation by
  itself.
- **`people.last_contacted_on`** (built, Q8) stays the only recency signal —
  one-tap "Log contact today," never inference.
- The two compose: flagged + logged → the dashboard shows recency and the
  stay-in-touch watcher may speak. Flagged + never logged → the dashboard
  shows "no contact logged yet" but the watcher stays silent (no signal, no
  nudge — the Q8 rule, unchanged). Unflagged → invisible to the dashboard
  regardless of logs; the Address Book still has them.
- **The watcher gets circle-scoped, with a backfill.** `Watcher::StayInTouch`
  today scans *everyone* with a `last_contacted_on`; under D38 it adds the
  flag to its `where`. That silently changes behavior for existing users
  unless the migration backfills `keep_in_touch = true` wherever
  `last_contacted_on` is set — logging contact *was* the opt-in until now, so
  the flag inherits it. No one's nudges change on upgrade day.
- **The circle is personal, not shared.** Modules read
  `Current.user.people`, not `visible_to` — the flag is the owner's intent,
  and you don't tend your spouse's circle. (Shared people still appear
  where they always did: the Address Book and other sections' filtered
  lists.)
- **Capture card** (the section's mini-FTUE, mirroring "What do you do for
  fun?"): the section page leads with **"Who do you want to stay close to?"**
  — picks from the Address Book plus quick-add by name — each answer sets the
  flag. Shrinks to an "Add someone" affordance once a circle exists.
- Later, optional per-person cadence (see §5); not needed for v1.

## 3. Page anatomy (D18 zones, People-shaped Browse)

*As built, this ships as the People lead panel under the D37 convention —
`Sections::Panels::People` + `sections/panels/_people.html.erb`; the shared
page files carry no People-specific code. The panel base gained
`hidden_browse` (the browse-zone counterpart of `hidden_tool_slugs`) so the
panel hides the roster grid and the events card it re-renders inside Coming
up.*

Act and Attend are unchanged — tool cards, then suggestions (birthday radar
and stay-in-touch will feed Attend). Browse rebuilds as modules:

1. **Coming up** — birthdays in the next ~30 days (straight off
   `people.birthday`, which imports already populate — no Events required)
   plus upcoming People-tagged Events. The "dates that matter" strip.
   Circle-scoped, same as everything here — a synced address book must not
   spray acquaintances' birthdays. Next-occurrence math (year wrap for
   December birthdays, Feb 29, month/day comparison in SQLite) lives in one
   `Person.birthday_within(days)` scope that the birthday-radar watcher
   reuses — solve once, use twice.
2. **Your circle** — kept-in-touch people, stalest first: name, relationship,
   "last contact 5 weeks ago" / "no contact logged yet", one-tap **Log
   contact** and **Reconnect**. This is the pull-side twin of the
   stay-in-touch watcher — same math, always visible, no nudge required.
3. **The lens lists** — People-tagged Tasks, Events, Goals, Notes as today,
   *minus* the Person grid (D38), plus the Address Book link line. The grid
   removal is the *People page only*: other sections' small filtered person
   lists (your cardiologist on Health, the landlord on Rights) are genuinely
   useful and stay.
4. **Capture card** when the circle is empty (§2), replacing the generic
   empty state — and offering the importer when the Address Book itself is
   empty, so the page is never a dead end.

**Picker scaling, everywhere people are chosen**: the tool form's `:person`
select and the capture card both enumerate all people, which degrades at
synced-address-book size. Cheap v1 that doubles as the flag's first payoff:
circle first, then the rest alphabetically. Typeahead is later polish.

## 4. Tools (each one declarative class on D19 infra; all Tier A)

Built already: **Reconnect** (the section's core promise) and **Plan a move**
(registered here for the address-change surface).

1. ✅ **"What do I say?"** *(chat, D29 — built)* — the flagship, and the relationship
   analog of the Rights letter family: social scripts for people who weren't
   handed them. Preset chips seed the first message — *check in on someone
   who's struggling, apologize, condolences, ask for help, set a boundary,
   invite someone, say no* — plus an optional `person` input so the
   conversation opens knowing the context. The chat shape matters: hard
   conversations need back-and-forth ("she replied this — now what?"), which
   is exactly what D29 built for the tutor. "Save a recap" files the plan.
2. ✅ **"Plan a get-together"** *(plan — built)* — occasion + who + an optional date →
   Goal + prep Tasks + the Event on the calendar. One mechanical honesty
   note for the builder: `plan_goal!` → `Goals::BreakDown` produces Goal +
   Tasks *only*, so the Event does not fall out of the plan pipeline — the
   tool creates it **by code** via the existing `Base#create_event` when a
   date is given (and the brief plans backwards from it, the
   prep-for-the-big-day pattern); with no date, the first task is "pick a
   date." The brief steers hard toward small, cheap, and scheduled — the
   taco night that actually happens beats the dinner party that never does.
   Covers PRODUCT.md's "event planning" line with zero new machinery.
3. ✅ **"Gift ideas"** *(draft — built)* — reads the person's notes and section overlaps
   (a hobby-buddy tag is half the answer) → 5–8 ideas sized to a budget line,
   placeholders naming what it doesn't know. Chained from birthday radar via
   the D28 pattern; multi-tags into Money when it ends in a planned purchase.
4. ✅ **"Make new friends"** *(plan — built)* — the widest loneliness funnel. Brief
   pushes the evidence-shaped path: pick a *recurring* venue (club, class,
   volunteering — one-off events don't compound), commit to showing up N
   times, follow-up scripts for turning acquaintances into plans.
   Cross-registers with Hobbies' find-your-people; same Tier-A honesty (never
   invents local venues).
5. **Situations, later** — "becoming a caregiver," "new baby," bereavement:
   the coordination-heavy life events PRODUCT.md names (caregiving,
   co-parenting logistics) are plan tools with rich briefs once demand shows,
   exactly like "moving" was.

**The one infra seam this slate needs: `Base#person_context`.** Reconnect
hand-rolls its person block (name, relationship, birthday, last contact, the
`people.notes` column) inside its own `user_prompt`. Gift ideas and
What-do-I-say need the identical block, so extract it into a shared helper on
`Tool::Base` first — the `section_context` pattern at person granularity,
`visible_to` the only read path — and refit Reconnect onto it. Three
consumers, one assembly, and when Q14 links land the helper is the single
place shared-history context gets added.

## 5. Agent (D20 watchers — SQL-first)

- ✅ **Stay in touch** (built, Q8) — unchanged.
- ✅ **Birthday radar** *(built)* — the section's cheapest delight:
  pure SQL over `people.birthday` (already imported for free), ~3 weeks out,
  fingerprinted per person per year. Accept = an all-day Event + a lead-time
  task; the suggestion offers Gift ideas and Reconnect prefilled (D28
  routing from a watcher — the stay-in-touch ← Reconnect pattern again).
  Scoped to the circle (§2) so an import doesn't spray 300 birthday nudges.
- **Cadence upgrade** for stay-in-touch — optional per-person cadence
  (weekly for mom, quarterly for college friends) replacing the fixed
  staleness window; shares its median-gap math with Hobbies' rhythm keeper
  (solve once, use twice). Ships only if the fixed window annoys real users.
- **Balance insight** — digest garnish, already the Hobbies pattern: a week
  ahead that is all deadlines and zero People-tagged anything gets named
  gently in the synthesis.
- **Event afterglow** *(deferred on Q14)* — a People-linked event passes →
  offer to log contact for its people. Closes the manual-signal loop without
  inference; needs person↔event links to exist first.

## 6. Groups: the community layer

Family, church, the D&D table, the mutual-aid crew — PRODUCT.md's
"communities" half. Groups are **user-created sub-lenses of People**: the D25
mechanism generalized (`sections.custom` was built section-agnostic;
`Hobbies::Lens` just needs its Hobbies-specificity lifted into a shared
service). Everything falls out the usual way: a group page with full
Act/Attend/Browse anatomy, group Events on the calendar, group Notes, member
People tagged into the lens, sharing via existing section grants ("share the
co-op lens with the household"). Community tools ride it later — meeting
agenda drafts, rotating-duty rosters, phone trees. Not the first wave, but
it is *why* the section must not collapse into a private-friends CRM: the
collective-capacity line of the mission lives here.

## 7. Cross-section dividends

- **× Hobbies** — hobby buddies tag both ways (HOBBIES.md §5 already claims
  the Reconnect upgrade); find-your-people and make-new-friends are the same
  funnel seen from opposite ends, cross-registered.
- **× Health** — "Mom's cardiology appointment" is the founding multi-tag
  example; caregiving Situations file Health + People; What-do-I-say's
  check-in preset is the soft edge of the caregiving surface.
- **× Money** — gift ideas budget line; a shared-expenses note multi-tags;
  group dues under a group lens.
- **× Career** — Reconnect works verbatim on professional contacts
  ("congratulate her on the new job"); networking is staying-in-touch with a
  different relationship value.
- **Situations** — "Moving" should spawn a reconnect-by-mail/see-before-you-go
  task over circle people (and later, a per-group heads-up); new-baby and
  caregiver Situations are People-heavy by construction.

## 8. Open question Q14 — person↔item links

Section tags answer "which lenses"; nothing answers "which *people*." An
attendees join (polymorphic `person_links`: person ↔ Event/Task/Note/Goal)
would buy: per-person history on the person page ("everything with Sam"),
gathering attendees, the afterglow watcher, and Reconnect context from shared
events. Cost: the first typed cross-primitive join beyond tagging, plus link
UI on every form — a real capture-friction risk (D16). Q8's rule extends to
any shortcut: name-matching may *suggest* a link, never assume one. Decide
when a second consumer demands it; afterglow and per-person history are the
queued consumers.

## 9. Build order

1. ✅ **The D38 split** — `keep_in_touch` flag (+ backfill from
   `last_contacted_on`, §2) + person-page toggle, the "Who do you want to
   stay close to?" capture, `StayInTouch` circle-scoping, section page
   rebuilt (Coming up / Your circle / lens lists sans Person grid / Address
   Book link), circle-first person pickers.
2. ✅ **Birthday radar** watcher (circle-scoped, sharing
   `Person.birthday_within` with Coming up; the Coming up rows offer Gift
   ideas and Reconnect prefilled).
3. ✅ **"Gift ideas" + "Plan a get-together"** — one draft, one plan, both
   thin classes on existing contracts, preceded by the
   `chosen_person`/`person_context` extraction (§4) and a new `:date` input
   kind.
4. ✅ **"What do I say?"** chat tool (second consumer of D29 after the
   tutor).
5. ✅ **"Make new friends"** plan tool.
6. ✅ **Groups** — D25 lens creation generalized into `Sections::Lens`
   (`People::Group` / `Hobbies::Lens` as its two front doors); community
   tools get their own design conversation after real use.
7. Deferred: Q14 links → afterglow watcher + per-person history, cadence
   upgrade, caregiving/co-parenting Situations.
