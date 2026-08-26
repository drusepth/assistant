# HOBBIES.md

Section deep-dive for **Hobbies** — design for how the section earns its place
across all three modes (D6). Everything here rides existing infrastructure
(D17 breakdown, D19 tools, D20 watchers) except where explicitly flagged. The
one new decision it needed — hobby representation — is **D25** in
`DECISIONS.md`; the first slice (sub-lenses, capture, and three tools) is
built, marked ✅ in §6.

## Why this section matters (mission tie)

Hobbies is not the "fun extra" section — it is the *meaning-making* section.
PRODUCT.md already names it: in a post-labor transition, purpose and creation
grow in importance. The wealthy have always had the infrastructure of a
fulfilling leisure life — teachers, clubs, studios, coaches, curated
communities. The target user mostly has an algorithmic feed optimized to keep
them scrolling *about* hobbies instead of doing them. The counter-move is the
same as everywhere else in the app: owned context + tools that push toward
**doing**, not consuming.

Design trap to avoid, named up front: hobby apps die by making *tracking* the
hobby. D16 discipline applies double here — capture stays near-zero, the
assistant does the filing, and every feature should end in a scheduled session,
a started project, or a human connection, not a better-groomed log.

## 1. Knowing the user's hobbies (the foundation)

Everything else in this doc needs to know *what the hobbies are* and *where the
user is with each one*. Two-part answer, both riding existing structures:

### Hobby = user-created sub-lens (D25 — built)

A hobby is not a Goal (it doesn't complete), not an Event (not dated), not a
Note (it's a lens, not a fact). It is exactly what a **section** is: a filter
over the shared primitive pool. A "Guitar" hobby *is* its practice Events, its
gear Documents, its jam-buddy People, its learn-the-solo Goals, its Notes.

So the proposal: hobbies are **user-created child sections of Hobbies** —
the first user-generated rows in the `sections` taxonomy (D12 built the
`parent_id` mechanism; the seeds just haven't needed it under Hobbies yet).
Everything then falls out for free, which is the lens model's whole sales
pitch:

- Per-hobby pages with the full Act/Attend/Browse anatomy (D18).
- Per-hobby calendar/Today filtering, multi-tagging ("climbing trip with Sam"
  = Hobbies→Climbing + People).
- Per-hobby sharing via existing section grants ("share my D&D stuff with the
  household").
- Tools registered on `hobbies` surface on every child page (the existing
  parent/subsection rule, inverted — needs a small registry tweak: parent
  tools appear on children, since we can't pre-register on lenses that don't
  exist yet).
- Later, per-hobby agent dials — the D20 dial machinery already lives on
  `user_sections`.

This was the first place users write to the taxonomy table; D25 resolved it:
lenses carry `sections.custom` (the only removable sections — removal keeps
the items, which just lose the tag), slugs share the global namespace with
numbered collision handling, colors inherit from the parent as the helper
always did, and the tool registry now surfaces parent-registered tools on
every subsection page.

### Hobby profile = the lens's own Notes

Alongside the lens, ordinary **Notes** tagged with it hold what tools need as
context: skill level, years in, gear owned, aspirations, taste, constraints
(budget, space, time), season (for the seasonal watcher below). No schema and
no special "profile" object — tools read the lens's notes (and goals and
documents) as their context, so the profile accrues from normal use.

### How hobbies get known

1. **The section page asks.** The Hobbies page leads with one question —
   "What do you do for fun?" — chips for common hobbies + free text. Each
   answer creates a sub-lens. This is the section's mini-FTUE and feeds Q5's
   design later. Once lenses exist the page leads with them instead: a
   "Your hobbies" card grid (each card a doorway with engagement signal —
   next planned event, open tasks/projects, or a dive-back-in invitation
   when quiet; `Sections::Summary`), with capture shrunk to an add-tile
   at the end of the grid. Lenses deliberately do *not* render as header
   chips — the list is unbounded and a chip cloud has no pull.
2. **The data confesses.** `Categorize*Jobs` already tag `hobbies`. When
   hobby-tagged items keep mentioning the same activity ("climbing" in four
   events and two notes), a watcher suggests: "Looks like climbing is a thing
   — want a Climbing lens?" Agent proposes, user disposes (D20).
3. **An interview tool.** "Tell me about a hobby" — a draft tool that asks the
   model to interview-summarize one free-text ramble into a structured profile
   note. Zero-friction onboarding for people who'd rather talk than tick chips.

## 2. Organize (mostly already built — name it, don't build it)

The lens model dividend: Hobbies-Organize is *done* in Milestone 1. What a
hobbyist stores maps 1:1 onto the six primitives:

| Life thing | Primitive |
|---|---|
| Projects (the sweater, the campaign, the restore job) | Goal + Tasks |
| Practice sessions, club nights, lessons, matches | Events |
| Gear manuals, receipts, patterns, sheet music, photos of the collection | Documents |
| Jam buddies, teammates, teachers, the guy at the shop | People |
| Session log, ideas, "what I learned," collection inventory | Notes |

Two small Organize-mode notes:
- **Collections** need no new model: a collection is Notes/Documents under the
  hobby lens (inventory note + photos). If collectors ever need real structure
  (fields, counts, values), that's a future conversation — not schema now.
- **Warranty/receipt docs** multi-tag into Money/Rights automatically via the
  existing categorizers — a hobby purchase dispute is already a Rights →
  Disputes draft-letter run away. Free cross-section win; nothing to build.

## 3. Tools (the meat — each is one declarative class on D19 infra)

All Tier A unless marked. Ordered roughly by funnel width.

### Plan tools (ride `Goals::BreakDown` + brief)

1. **"Start a hobby"** — the widest funnel and the flagship. Input: what
   you're curious about + optionally why. Brief steers hard toward the
   *cheapest possible first taste*: a scheduled first session, a
   borrow-don't-buy gear task, a find-your-people task, a tiny first project —
   explicitly counter to gear-acquisition-syndrome and course-hoarding. Also
   creates the sub-lens + profile note. This is "help me have a life," the
   section's front door.
2. **"Start a project"** — per-hobby. One line ("knit a sweater," "build a
   MAME cabinet") → Goal + steps tagged with the hobby. Nearly identical to
   Learn-something with a making-framing brief; proves briefs specialize.
3. **"Level up"** — reads the profile note + recent hobby items → a structured
   practice plan targeting a named skill: Goal + scheduled practice Events
   with focus per session, not vague "practice more."
4. **"Prep for the big day"** — recital, race, exhibition, tournament, con.
   Input: the date + the thing. Plans backwards from the date (the brief's one
   job); the event itself lands on the Calendar.

### Draft tools (reviewable Notes + optional follow-up Tasks)

5. **"What should I make next?"** — the idea generator. Reads profile + past
   project Goals + gear notes → a menu of 5–8 project ideas sized to skill and
   stash, each one click from becoming a Goal (accept = run Start-a-project
   prefilled — the same tool-chaining pattern as Reconnect ← stay-in-touch).
   This is the honest Tier-A version of "generate interesting new content":
   the model's evergreen craft knowledge applied to *your* context, framed as
   sparks, never as news.
6. **"Coach me this week"** — reads recent session notes + profile → this
   week's practice plan: drills, one stretch challenge, one thing to stop
   doing. The Education tutor wearing a coach's whistle.
7. **"Find your people"** — the Q9 reframe of "find meetups nearby." Tier A
   version: reads the hobby + your city (profile note) → a search checklist
   (Meetup, library boards, community centers, guilds, game stores, Discords,
   park district catalogs — per-hobby-appropriate), what to ask when you show
   up, and a "check these this week" Task. Same outcome, no capability lie.
   **Tier B upgrade later** (same slug, per Q9): real local listings.
8. **"Find a class"** — same split. Tier A: where classes hide for this hobby,
   questions that separate good teachers from bad, budget framing, a script
   for the intro call. Tier B later: actual listings.
9. **"Gear check"** — "do I actually need X?" Reads gear notes + profile →
   an honest buy/borrow/wait draft with what-to-look-for criteria. The
   anti-affiliate-slop counterprogramming; multi-tags into Money when it ends
   in a planned purchase.
10. **"Show & tell"** — turns a finished project's photos/notes into a
    shareable writeup (Document/Note). Post-labor meaning-making made
    visible; pairs with household sharing ("show the family").

### Content surfacing, honestly

✅ **The reader shipped the honest half of this (D-feed-reader,
`docs/READER.md`)**: the user follows the blogs, subreddits and channels
behind their hobbies, and everything they publish lands in one
chronological river, filterable by hobby — no crawler, no third-party
index, no capability the app doesn't have, and no model call. Deliberately
*not* ranked: these sources were each chosen by hand, so there is nothing
to sift, and a river you can predict is the whole point. ✅ **D-hobby-feeds**
(`docs/HOBBIES_HUB_PLAN.md`) then brought the river onto *this* page — one per
hobby card, with `/reader` as the everything-view — and let the model file each
new subscription under the hobbies it belongs to, with anything it can't place
landing in one lens called Other Interests. It resolves the
*sources* half of the split below without waiting on Q9; what still waits
is anything the app would have to go and find on its own (local meetups,
classes, listings).

"Surface interesting new content" splits cleanly on the Q9 line:

- **Tier A (ship first):** generated *evergreen* content from model knowledge
  × owned context — ideas, challenges, technique deep-dives, "this month, go
  deep on X" digests. Frame as coaching/prompts, never as current events; the
  model-agnostic constraint means we can't promise freshness.
- **Tier B (deferred with Q9):** live meetups/classes/events, new releases,
  community content, weather-aware nudges. When capabilities land, the Tier A
  tools above upgrade in place rather than spawning new ones.

## 4. Agent (D20 watchers — SQL-first, all of these are cheap)

- ✅ **Neglected hobby** — the flagship, shipped (`Watcher::NeglectedHobby`)
  alongside the D20 watcher slate. No items tagged with a hobby lens added,
  scheduled, or checked off in 6 weeks, nothing upcoming, and the lens older
  than the window → one nudge; accept = an all-day session Event, tagged
  Hobbies + the lens, on the first free day in the next week. Monthly
  fingerprint buckets (the goal-stall convention) let a dismissed nudge
  fairly return. Pure SQL over `section_taggings` — no new signal needed,
  and the Hobbies dial in Settings tunes or silences it like any watcher.
- **Rhythm keeper** — refinement of the above: learn each hobby's natural
  cadence (median gap between hobby-tagged events) and nudge on *broken
  rhythm* rather than a fixed N. Shares its math with Q8's recency design —
  solve once, use twice.
- **Project stall** — already exists (goal-stall watcher, M3 slate) and covers
  hobby projects for free. Lens dividend; zero work.
- **Seasonal opener** — deterministic and delightful: profile note says
  gardening → February brings "seed-starting season — plan the beds?"
  Ski gear in the vault → November nudge. A tiny hobby→season lookup + the
  profile note; no LLM, no web.
- **Balance insight** — Dashboard-digest garnish (M3.3): when the week ahead
  is all deadlines and zero hobby-tagged anything, the synthesis says so.
  Hobbies as the wellbeing counterweight — the mission's meaning-making line
  showing up in the product's voice.
- **Event radar** *(Tier B, deferred)* — local happenings, releases, exhibits.
  Waits on Q9/Q10 like everything external.

## 5. Cross-section dividends (the lens model selling itself)

- **× Education** — already proven: Learn-something files hobby topics under
  Hobbies today (there's a test asserting it). Learning-the-skill vs
  doing-the-hobby is a gradient; multi-tagging dissolves the boundary.
- **× People** — hobby buddies tag both ways; Reconnect prefilled with
  shared-hobby context ("ask how his kiln build went") is a strictly better
  Reconnect; household shared hobbies (family game night) ride cross-user
  grants (D9).
- **× Money** — hobby subscriptions surface in the Subscriptions audit; Gear
  check feeds Budget; receipts/warranties land in the vault multi-tagged.
- **× Health** — physical hobbies are exercise; hobby cadence is a
  mental-health signal the balance insight can name gently.
- **× Career** — the hobby→side-gig ramp ends at Career's
  small-business-in-a-box; "Show & tell" writeups are half a portfolio.
- **Situations** — "Moving" (M2.4) should spawn a find-your-people task per
  active hobby in the new city; "retiring," "empty nest," and "recovering from
  burnout" are hobby-heavy Situations for the later slate.

## 6. Build order

1. ✅ **Representation (D25)** — sub-lens creation (`Hobbies::Lens`), the
   "What do you do for fun?" capture on the Hobbies page, lens removal,
   parent-tool surfacing on subsection pages.
2. ✅ **Two tools to make the section alive** — "Start a hobby" (plan; also
   creates the lens) + "What should I make next?" (draft idea menu). Both
   Tier A, one class each.
3. ✅ **"Find your people" (Tier A)** — the meetup ask, honestly scoped:
   guide note + check-this-week tasks; upgrades in place when Q9 resolves.
4. ✅ **Neglected-hobby watcher** — shipped on the D20 suggestions core
   (`suggestions` table, Attend zone, Dashboard feed, accept/snooze/dismiss,
   weekly/daily scans honoring the Settings dials).
5. ✅ **The reader** (D-feed-reader, `docs/READER.md`) — feeds per hobby,
   one chronological river, and per-item verbs that end in a task. The
   daily surface the section was missing.
6. **Tier B upgrades** (real meetups/classes/event radar) when Q9 resolves.
