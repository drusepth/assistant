# PEOPLE_CIRCLES.md

The People page redesign: **every collection of people is a card, and the
circle is one of them.** Sub-plan of `docs/PEOPLE.md` (which stays the
section's deep-dive); the decision is **D-people-circles**. Nothing here
changes the D-people-dashboard split — the Address Book is still the roster,
the section page is still the dashboard. This is about the *shape* of the
dashboard's middle.

*Waves 1–3 are built (2026-08). Wave 4 — community tools — still waits on a
real group living in a lens, which wave 2 finally makes possible. Where the
build learned something the plan had wrong, the text below says so inline
rather than pretending it went to plan.*

## 1. What was wrong

The page said "here are the people in your life" three times, in
three different visual languages, and none of them is the one you'd draw:

| Surface | Rendered as | Problem |
|---|---|---|
| **Groups** | a row of `Ui::SectionChipComponent` chips | A chip is a *filter token*, not a place. It carries no faces, no count, no next thing — nothing to want. And it prints `qualified_name`, so every group reads "People · Church": the prefix is louder than the name. |
| **Your circle** | a full-width card of person rows | The one collection that gets rows, actions, and recency — special-cased because it was built first, not because it's different in kind. |
| **Address Book** | a one-line text link | Correct and fine. Stays. |

So the two things that *are* the same idea — a set of people you're tending —
look nothing alike, and the one that looks least like anything (the chips) is
the one carrying the community layer the mission actually cares about
(PEOPLE.md §6). A user reading the screenshot can't tell that "Church" and
"Your circle" are the same sort of noun.

There's a second, quieter failure underneath the visual one: **you cannot put
a person into a group from anywhere on this page.** Group membership is a
`section_tagging`, and the only UI that writes one is the section picker in
the *Advanced* drawer of the person edit form. So groups are born empty, stay
empty, and render as a chip that leads to an empty page. "Test group" sitting
next to "Church" with no way to tell them apart is that bug wearing a costume.

## 2. The one idea

One card per collection of people. The circle is the first card. Groups are
the rest. A dashed tile at the end starts a new one.

```
┌ Your circle ──── 🔒 ┐ ┌ Church ─────────────┐ ┌ Book club ──────────┐
│ (◍(◍(◍(◍(◍  +4      │ │ (◍(◍(◍  +12         │ │ (◍(◍(◍(◍            │
│ Your circle         │ │ Church              │ │ Book club           │
│ 9 people · 3 have   │ │ 15 people · Potluck │ │ 4 people · nothing  │
│ drifted             │ │ Sat Sep 3           │ │ planned yet         │
│ ─────────────────── │ │ ─────────────────── │ │ ─────────────────── │
│ Add someone         │ │ Add someone  Plan…  │ │ Add someone  Plan…  │
└─────────────────────┘ └─────────────────────┘ └─────────────────────┘
┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐
│ Start a group…      │   ← dashed add tile, the `_hobby_add_tile` precedent
└ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
```

Same grid, same card atom, same rules everywhere in the app: this is the
Hobbies lens grid (`sections/_hobby_card`) with faces on it. That's the point
— we are not inventing a People-shaped widget, we're deleting one.

## 3. Card anatomy

Top to bottom, and every line has a job:

1. **The avatar stack** — up to five overlapping faces, `+N` bubble for the
   rest. This is the whole reason the redesign is worth doing: a group is its
   people, and a card that shows four faces you recognize is a card you touch.
   Each face is its own link to that person's page, with the name on hover, so
   the card is a doorway to *both* scales at once — the group and the
   individual. Real photos when they exist (D-contact-photos already gave
   contacts faces), initials circles when they don't; an instance where nobody
   uploaded anything still looks composed, because the initials tints were
   always there.
2. **The name** — plain `name`, never `qualified_name`. The card is already
   inside People; the prefix is noise. (The chip component keeps
   `qualified_name` — it's right *there*, on an item that could be tagged
   anything.)
3. **One line of signal** — member count, then the single most useful fact,
   in the `Sections::Summary` spirit: the next group Event, else an upcoming
   birthday inside the group, else open tasks, else an honest invitation
   ("Nothing planned yet"). The circle's version of the signal is its own
   ("3 you haven't heard from in a while"), because staleness is what the
   circle is *for*.
4. **Two actions, both ending in contact.** `Add someone` (§5) and `Plan
   something` — `new_tool_run_path("get_together", inputs: { who: group.name })`,
   which needs no tool change: GetTogether's `who` is already free text
   ("Optional — names, or 'the book club'"). PEOPLE.md's anti-CRM rule holds:
   no action here ends in a better-groomed record.

**Empty group** — no members yet: the stack slot renders a soft dashed ring
instead of faces and the signal line reads "No one here yet". The ring is
there to hold the row's height, so a brand-new group still lines up with the
cards beside it; it carries no label, because the signal line one line down
already says the words. A new group should look like an invitation, not a
mistake.

**One more thing the build changed**: stone is *not* in the face-tint cycle.
With four tints cycling, the `+N` bubble — also stone — was indistinguishable
from a face at a glance. Faces cycle primary/amber/sage by person id (stable,
so the same person keeps their tint across cards), and stone belongs to the
bubble alone.

**Markup gotcha, worth naming before someone hits it**: `_hobby_card` wraps
the entire tile in `link_to`. This card can't — it contains its own links and
buttons, and an `<a>` inside an `<a>` is invalid and breaks the touch target.
Build it as a `<div class="card group">` with the *title* as the link and
Tailwind `group-hover:` classes carrying the whole-card hover affordance.

## 4. Why the circle is not turned into a section

The tempting simplification is to make the circle a real `Section` lens so the
grid is genuinely homogeneous. **No.** Sections are household-shared taxonomy;
the circle is `people.keep_in_touch`, per-user and deliberately personal —
"the flag is the owner's intent, and you don't tend your spouse's circle"
(PEOPLE.md §2). Making it a section would quietly share it with the household,
which is exactly the kind of hidden default D9 forbids.

So they unify at the **presentation** layer only. A small value object gives
both shapes one interface, and the partial never asks which it got:

```ruby
People::Circles::Card = Struct.new(
  :section,    # nil for the circle — `card.circle?` reads off that
  :name, :path, :members, :member_count, :signal, :private,
  keyword_init: true
)
```

And because they *are* different — one private intent, one shared lens — the
circle card wears a small `Only you` lock chip. That difference is real; the
redesign shouldn't hide it just because the boxes match.

## 5. Membership: the missing verb

This is the functional half, and the reason the visual half sticks.

- **`Add someone` on a group card** opens the same capture the circle already
  has — since D-person-picker, one type-to-find combobox that searches the
  address book (circle first within each match rank) and offers to add a
  typed name as a new contact. The original `<select>` over everyone didn't
  survive a real import.
- **New service `People::Membership`** — `add(viewer, section, person_id: nil,
  name: nil)`: finds or creates the Person (`viewer.people.create!` when the
  name is new), then `find_or_create` the `SectionTagging`. Idempotent, so a
  double-tap can't duplicate. `remove(...)` deletes only the tagging — the
  person keeps their other tags, matching how group deletion already behaves.
- **Removing a member** lives on the group page, not the card: hovering a face
  in a grid to reveal a destructive control is how people remove their mom by
  accident.
- **Groups become reachable from the person side too**: the person page grows
  a small "Groups" line with the same add affordance. Same service, second
  consumer, and it's where someone actually thinks "oh, she's in the book club."

Membership stays a plain `section_tagging` throughout — no new join table, no
Q17 person↔item links. This plan does not need them and shouldn't pull them
forward.

## 6. The page, top to bottom, after

1. **Capture** — unchanged ("Who do you want to stay close to?" / "Add someone
   to your circle").
2. **Coming up** — unchanged (birthdays + People-tagged events).
3. **Circles grid** — §2. Replaces *both* the Groups chip card and the "Your
   circle" rows card.
4. **Reach out** — the stalest five circle people as rows, with one-tap
   `Log contact` and `Reconnect`. This is the part of "Your circle" that
   earned its rows: it's the pull-side twin of the stay-in-touch watcher
   (PEOPLE.md §3.2), and it must not be a grid — the whole point is name,
   recency, and a button. What it is *not* any more is the entire circle: the
   full circle is one tap away on the circle card.

   *Built as "Reach out", not the planned "Been a while": the list has to
   include people with no logged contact (otherwise a fresh circle loses the
   one-tap loop entirely), and "been a while" is a claim you can't make about
   someone you've never logged. An action for a title is honest for both.*
5. **Address Book link line** — unchanged.
6. Lens lists (tasks, events, notes, goals) — unchanged.

Net: one card and one chip cloud out, one grid in, and the page stops
answering the same question three ways.

The circle card's link target is the Address Book filtered to the circle —
`people_path(circle: "1")`, a one-line scope in `PeopleController#index` plus
a filter pill on that page. Cheaper than a new page, and it puts the full
roster view where roster views live.

## 7. Files

New:

- `app/components/ui/avatar_stack_component.rb` + `.html.erb` — layered
  avatars. `people:`, `size: :sm`, `max: 5`, `link: true`. Renders
  `Ui::AvatarComponent` per face inside a `flex -space-x-2` row, each with
  `ring-2 ring-surface` so the layers separate against any card, and
  `hover:z-10 hover:-translate-y-0.5 transition` for the lift. Overflow is a
  `+N` bubble in the same size and ring. It renders *through* AvatarComponent,
  never around it — one face, one place (D-user-avatars). Named consumers
  beyond this page, so it isn't a one-off: photo album tiles (`photo_people`),
  household member lists in Settings, and event attendees when Q17 lands.
- `app/services/people/circles.rb` — builds the `Card` list: the circle card,
  then one per `section.children`, with members and signals batched (§8).
- `app/services/people/membership.rb` — §5.
- `app/views/sections/_circle_card.html.erb` — the card.
- `app/views/sections/_circle_add_tile.html.erb` — the dashed "Start a group…"
  tile (the existing `groups#create` form, restyled after `_hobby_add_tile`).
- `app/views/sections/_circle_add_person.html.erb` — the one capture for "put
  a person here", shared by the circle card, every group card, and the group
  page.
- `app/controllers/people/memberships_controller.rb` + routes for add/remove.
- `app/services/sections/panels/people_lens.rb` +
  `app/views/sections/panels/_people_lens.html.erb` — the group page's own
  lead panel: members, remove, add. It needed one extension to `Panel.for`,
  because a group's slug is whatever the user typed and can't be known by a
  class name: a panel is resolved by slug first, then by
  `Sections::Panels::<Parent>Lens`. Hobby lenses still resolve to nothing —
  no `HobbiesLens` class exists — so nothing else changed.

Changed:

- `app/services/sections/panels/people.rb` — `circle_cards` replaces `groups`;
  the reach-out rows and the capture's "does a circle exist" both read off
  the circle card rather than re-querying, since it already loaded the circle
  stalest-first with avatars attached.
- `app/views/sections/_people_hub.html.erb` — the grid and the trimmed
  "Reach out" card.
- `app/views/people/index.html.erb` + controller — the `circle` filter.
- `app/views/people/show.html.erb` — the Groups line.
- `docs/DESIGN.md` — one line in the component registry for the stack.

**Not** changed: `SectionsController`, `sections/show.html.erb`,
`SectionsHelper` — D37 forbids it, and this needs none of them.

## 8. Queries

The grid is N+1 bait: every card wants members with attached avatars, and
every card wants a signal. All of it batches.

- **Members**: one query for group members —
  `Person.visible_to(viewer).joins(:section_taggings).where(section_taggings:
  { section_id: group_ids }).with_attached_avatar`, selecting
  `section_taggings.section_id`, grouped in Ruby — plus the existing
  `viewer.people.circle` for the circle card. Two queries, however many
  groups there are, and a test asserts exactly that.

  *The plan wanted to cap that fetch and get `+N` from a separate count.
  The build doesn't: the birthday signal needs every member's birthday and
  the count needs every member anyway, so a capped fetch would have bought a
  third query to undo itself. Rows are cheap; round trips aren't.*
- **Signals**: `Sections::Summary.for(viewer, groups)` already returns next
  event + open tasks + active goals in three batched queries. Reuse it as-is;
  don't touch the class (shared file, and it already does the job).
- **Visibility**: group members go through `visible_to` (a group is a shared
  lens and can hold a spouse's contact); the circle stays `viewer.people`.
  This asymmetry is deliberate and is the same one PEOPLE.md §2 already draws.

Test the batching, not just the render: `People::CirclesTest` builds three
groups of two and asserts the member queries stay at two, because this is
precisely the grid that silently degrades after a CardDAV sync.

## 9. Waves

*1–3 built (2026-08); 4 still waiting, on purpose.*

1. ✅ **The grid.** AvatarStack + `People::Circles` + `_circle_card` + add tile;
   chips and the circle roster come out; "Reach out" replaces the full
   list; `People ·` prefix gone. Ships as a pure cleanup — no new verbs, so it
   can land and be judged on its own.
2. ✅ **Membership.** `People::Membership`, `Add someone` on every card, the
   group-page member list with remove, the person page's Groups line. This is
   what makes wave 1 true rather than decorative.
3. ✅ **Signal and delight.** Per-group next-event/birthday line, `Plan
   something` prefilled, the circle's drift count, hover lift, the Address
   Book circle filter, an honest empty state per card.
4. **Later, unchanged from PEOPLE.md §6.** Community tools — meeting agendas,
   rotating duties, phone trees — still wait for a real group to live in a
   lens first. This plan is the thing that makes that wait falsifiable: after
   wave 2 a group can actually hold people, so we'll find out.

## 10. Deliberately not doing

- **No group avatars/photos.** A group's face is its members' faces. An
  uploaded group photo is a second, worse answer to a question the stack
  already answers, and it's a capture chore (D16).
- **No group roles, admins, or invites.** Groups are lenses, not accounts.
  Sharing already exists through section grants.
- **No drag-and-drop between cards.** It's the fun idea that costs a week and
  breaks on a phone, which is the device this page is being designed on.
- **No Q17 person↔item links.** Still waiting for a second consumer.
- **The circle does not become a section** (§4).
