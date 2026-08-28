# TASKS_PAGE_PLAN.md

Build plan for restructuring the **Tasks page** around its two modes of
thinking: high-level life planning with goals, and daily task tracking. The
decisions here are logged as **D-tasks-two-surfaces**, **D-goal-shape**,
**D-goal-capture-routing**, and **D-goal-pause** (`bin/decisions`), and D17
remains the foundation they amend.

---

## 1. The problem

D17 merged Goals and Tasks into one section, correctly: a goal is broken into
day-sized tasks, so they are one workflow, not two pages. But the page that
shipped leads with the *slow* half of that workflow. Active goals render as a
grid of tall gradient cards above the board, and on a phone they stack one per
row — four goals is four screens of static content between the user and the
Today column. The page a user opens ten times a day opens on the thing they
touch ten times a year.

The two cadences are the whole story:

- **Tasks** change state constantly — created, pulled into Today, completed,
  bumped to tomorrow. This is the daily surface.
- **Goals** are added or retired a handful of times a year, and *assessed*
  maybe weekly. This is a reflective surface.

Interaction frequency should decide screen real estate. Everything below
follows from that one rule.

## 2. The shape: one section, two surfaces (D-tasks-two-surfaces)

Not a mode toggle — a toggle between peers forces a decision on every visit
and hides daily state behind it. Hierarchy instead, which is also where the
industry converged (Things and Todoist open on Today with projects one level
away; Asana puts Goals in a tab that links down into work; OKR tooling treats
goals as a review *cadence*, not a dashboard):

**The board surface (default).** Top to bottom:

1. The capture box, unchanged in promise: one input, "what do you want to
   accomplish?", big or small.
2. The **goals strip** — the compact row D17 originally specified. One
   horizontally-scrollable line of small chips: title, progress or momentum
   (§4), and at most one flag ("no next step", "quiet for 6 weeks"). ~72px,
   not four screens. The strip is a doorway to the Goals tab, not a
   dashboard.
3. The board, immediately below — Today above the fold on a phone.

**The Goals tab** (`tasks?tab=goals`, same controller action, board is the
default tab). The planning destination: the big gradient cards for active
goals, a Paused shelf (§5), and the Achieved archive. The archive is kept on
purpose — years of finished goals are the product's proudest asset, and the
eventual "year in goals" retrospective (§7) renders from it.

**The goal page is the bridge between the modes.** Submitting the capture box
navigates *into the new goal's page*, where the breakdown streams in: the
user watches the plan form, edits it, pulls a step into Today — planning
flows into doing instead of materializing off-screen. Next morning the
scheduled steps surface themselves on the board (D17's due-today logic) and
the goal has receded to a chip.

### Strip ordering is signal, not chrome

Deterministic, computed in Ruby over the handful of active goals — never
`created_at` (carries no information), never a model call:

1. Goals with a step in Today — what you're working on now.
2. Goals **adrift**: no open step that will ever surface itself (nothing
   dated, nothing pulled into Today) or no steps at all. These carry the
   "no next step" flag; an undated later-bucket task never resurfaces under
   D17's Today logic, so an adrift goal silently exits daily life unless the
   strip says so.
3. Everything else, by recency of progress.

## 3. Capture routing: the box stays, the model sorts (D-goal-capture-routing)

D17's box always created a Goal, so "buy cat litter" became a goal card with
a progress bar — permanent noise in the planning surface. The fix keeps the
box's promise (never pre-categorize) and moves the judgment where judgment
already happens: `Goals::BreakDown` returns a verdict `kind` alongside the
plan.

- `kind: "goal"` — exactly today's behavior: sections, target date, steps.
- `kind: "task"` — the input is a single day-sized action. One dated,
  section-tagged Task is created, the placeholder Goal is deleted, and the
  goal page the user is sitting on stream-replaces its planning container
  with "this was day-sized, so it went straight to your board" plus the
  task's row.

Routing applies only to **bare captures** — a non-append run on a goal with
no steps, no description, no hand-set sections, no target date. The full goal
form is an explicit choice and is never second-guessed (D16). With no model
configured, nothing routes and every capture stays a Goal: off, not
approximated (D-no-keyword-logic).

## 4. Progress framing: finite vs. ongoing (D-goal-shape)

"Make new friends — 11%" is a lie with a progress bar. Percent is honest for
goals with a finish line and dishonest for aspirations, where it also jumps
around on every re-plan. The same breakdown call classifies each goal's
`shape`:

- **finite** → the percent climb stays (it's true, and it's the satisfying
  part).
- **ongoing** → momentum instead: "2 steps this week", or "last progress
  12 days ago", or "no progress yet". Honest across re-plans; never a
  verdict on an open-ended aspiration.
- `shape` nil (hand-created, no model, pre-existing) → percent, the status
  quo fallback.

Set once, never reclassified by later append runs (D16 discipline). Momentum
is computed from `tasks.completed_at` — no new counters.

## 5. The guilt museum, defused (D-goal-pause)

The dominant failure mode of goal products over years of use: stalled goals
accumulate into a wall of reproach and the user stops opening the app. Three
defenses, two built now:

- **Paused** joins the status enum. One click parks a goal off the strip and
  into the Goals tab's Paused shelf; one click resumes. No confirmation
  ceremony, no "are you sure" — shelving "learn guitar" for December is a
  plan, not a failure.
- **Staleness is said out loud, gently.** An active goal with no movement in
  six weeks (`Goal::STALE_AFTER`, computed from timestamps already written)
  gets a quiet "no movement in 6 weeks" marker and sorts into the strip's
  attention band. Information, not a red badge.
- **The agent check-in is deferred to Milestone 3** (D20): "this hasn't
  moved in six weeks — still matter? fresh plan, or shelf it?" is designed
  here but belongs behind the agent aggressiveness dials; a nudge that
  can't be dialed is a nag. When it lands, "shelf it" resolves to the
  paused state built now.

Re-planning must stay cheap and non-destructive, or users abandon goals
rather than fix plans: "suggest more steps" already appends without
clobbering, and pruning stays one click (D16). A fuller "re-plan around
what's done" pass rides the same seam later.

## 6. The board on a phone (D-tasks-two-surfaces)

Three kanban columns stacked vertically means Later buries Today and Done is
always a scroll away — half of the original complaint, independent of goals.
On small screens the columns become **swipeable panes** (CSS scroll-snap,
`min-w-full snap-center`) under a `Later | Today | Done` tab bar, **opening
on Today**; a small Stimulus controller (`board_panes`) sets the initial
pane, syncs the tab highlight to swipes, and scrolls on tab tap. Desktop
keeps the three-column grid; the controller does nothing at `lg:` and up.
Column DOM order stays Later / Today / Done so desktop reads
left-to-right as backlog → now → done.

## 7. Explicitly deferred, so it stays decided

- **Agent staleness check-in** — Milestone 3, per §5.
- **Yearly retrospective** ("you finished 3 goals and 214 tasks in 2026") —
  cheap later, enabled now by keeping the Achieved archive and
  `completed_at`; turns the archive from clutter into the retention feature.
- **Habits.** "Exercise 3×/week" is neither a Goal nor a Task, and users
  will type it into the box. For now the breakdown schedules a week or two
  of dated tasks — imperfect but not nonsense; a real recurrence answer is
  its own future plan and should not be improvised inside this one.
- **Household goal assignment** — a shared goal's steps landing in a
  specific member's Today. Visibility is already answered by access grants;
  assignment is not, and waits for a real use case.
- **One source of daily truth** is a standing constraint, not a feature:
  Today/Inbox, Dashboard, and section pages link into the board rather than
  reimplementing "what should I do today".

## 8. Build order (this branch)

1. Migration: `goals.shape` (string, nullable); status enum gains
   `paused: 3`.
2. `Goal` model: shape validation, pause/resume, momentum + staleness +
   next-step/adrift helpers, strip attention sort.
3. `Goals::BreakDown`: `kind` + `shape` in prompt and result; conversion
   path (bare captures only) creating the task, deleting the goal, and
   broadcasting the goal-page replace.
4. Controllers/routes: capture redirects to the goal page (`return_to`
   still wins); `pause`/`resume` members; `tasks#index` serves both tabs.
5. Views: strip partial, tab bar, goals panel (active / paused / achieved),
   shape-aware progress on cards, goal-show pause button + converted
   partial.
6. Mobile board panes + `board_panes` Stimulus controller.
7. Tests across all of the above; rubocop; status entry.
