# EDUCATION_PLAN.md

Build plan for the **Education hub**: the section that grows from two tool
cards into a personal school — a curriculum spine any household member can
learn anything on, at their own pace, taught through their own interests,
with progression measured the way the learning science says to measure it
and the paperwork a household schooling on its own terms actually needs.

Decisions here are logged as **D-education-spine**, **D-curriculum-commons**,
**D-mastery-evidence**, **D-review-scheduler**, and **D-learning-record** in
`DECISIONS.md`. Open questions are **Q-education-jurisdictions**,
**Q-education-assessment-trust**, **Q-education-materials**, and
**Q-education-fsrs-tuning**.

**Status: W1–W5 are built** (the spine and commons, the evidence machine
and its tools, the FSRS review engine, personalization and its watchers,
the household view and the record generators). W6 remains the horizon it
was designed as.

---

## 1. What we're building and why

Education is where the mission's inequality argument is sharpest, because the
gap has been measured. Bloom's **two-sigma problem** (1984): students taught
1:1 with mastery learning perform two standard deviations above students in a
conventional classroom — the average tutored kid beats 98% of the class. The
finding never failed to replicate; it just never scaled, because tutors cost
$40–100 an hour and mastery pacing is impossible when one teacher runs thirty
learners on one calendar. So the wealthy buy the two sigmas retail, and
everyone else gets batch processing: age-graded cohorts, a fixed bell
schedule, teach-to-the-middle, and a report card that records how much of the
material you *hadn't* mastered when the calendar said time was up.

School holds **time fixed and lets mastery vary** — everyone gets a semester,
and the spread between learners comes out as grades A through F. Mastery
learning turns that inside out: **mastery is fixed and time varies**. You do
not move past fractions until fractions are yours; how long that takes is
yours too, and it stops mattering the day it's done. That inversion is the
whole revolution this hub is built on, and it is structurally impossible in
a classroom and trivially possible 1:1 — which is exactly what an AI tutor
makes free. The rented versions of this are already being sold as
subscriptions; the counter-move is the same as everywhere else in this app.
Self-hosted, the tutor is yours, the curriculum is editable text you own, the
record of what your kid struggled with in March belongs to your household and
not to an edtech company's engagement dashboard, and the model behind it is a
swappable commodity (D2). The memory layer — what's mastered, what's rusty,
what clicked, what to review Thursday — is the durable asset, and it's the
part no one can repossess.

What the hub is *for*, concretely, spans four households:

- **The kid with homework tonight** — explain-anything help and a patient
  tutor that remembers Monday's session on Tuesday (built: the Tutor tool).
- **The homeschooling family** — a real curriculum spine: core subjects,
  placement, mastery tracking, and the portfolio/transcript/hours paperwork
  that makes schooling-at-home legally practical instead of heroic.
- **The adult who was failed the first time** — numeracy, reading, financial
  literacy, civics, at their own pace, with zero shame and placement that
  starts from where they are, not from a grade level.
- **The curious** — learn anything: the guitar-theory, ancient-history,
  small-engine-repair long tail, taught through what you already love.

And the two features that make it *this* app's education hub rather than a
courseware clone:

- **Personalized subjects**: the app already knows your Hobbies, Career, and
  Goals lenses, so it can *suggest* what's worth learning (theatre lens →
  public speaking; skateboarding → the physics of motion; a job-search goal
  → the reskilling path) with the reason printed on the card.
- **Personalized teaching**: the same knowledge threads *into* the teaching —
  ratios taught through skate geometry, chemistry through the sourdough
  starter, percentages through the household's actual budget. Interest
  framing is engagement fuel; mastery still gates on retrieval (§4), so the
  fun can never fake the learning.

Deliberately **not** in scope: accreditation or diplomas (we produce
*evidence*, §7), video/interactive content production (Q-education-materials),
grading against age-grade norms (pace anchors are the learner's own), and any
engagement casino — no XP, no leagues, no streak-shaming. The metric that
matters is retention, not minutes (the HOBBIES lesson: never make tracking
the hobby).

---

## 2. The learning science floor

"Lean on the industry standard" means the effects that survived replication,
each mapped to a *mechanism* — a thing in the schema or a rule in a prompt,
not a feature named after a buzzword. This table is the spec the rest of the
document implements:

| Effect (the evidence) | Mechanism in the app |
|---|---|
| **Mastery learning** (Bloom) — advance on demonstrated mastery, never on seat time | Per-topic mastery states advanced only by evidence (§4); no grades, no calendar gates |
| **1:1 tutoring** (Bloom's two sigmas) | The Tutor tool, upgraded to know its place in the curriculum (§6) |
| **Retrieval practice** (Roediger & Karpicke) — recall *causes* learning; re-reading only feels like it | Every topic gates on a retrieval check; lessons end by asking, not summarizing; quizzes mint review items |
| **Spaced repetition** (Ebbinghaus → SM-2 → **FSRS**) — review just before predicted forgetting | `review_items` scheduled by FSRS, the open modern standard (Anki's default since 23.10) — deterministic arithmetic, no model required (§5) |
| **Interleaving** (Rohrer) — mixed practice beats blocked practice | The daily review queue draws across all subjects by construction |
| **Formative assessment** (Black & Wiliam) — low-stakes checks that steer instruction | Placement finds the starting edge; checkpoint results reshape the plan; a wrong answer aims the next question at the gap (already the Tutor's rule) |
| **Zone of proximal development** (Vygotsky) — teach at the edge of ability | Placement + mastery states tell every prompt where the edge is |
| **Self-explanation** (Chi) — explaining beats being told | Socratic-first tutoring (built); "teach it back" as the strongest mastery evidence |
| **Deliberate practice** (Ericsson) — targeted reps on the weakest sub-skill | Skill subjects break into practicable micro-topics; `rusty` topics resurface first |
| **Spacing + paced plans** — distributed beats massed | Learn-something plans are paced by design (built); pacing whispers stay honest, never shaming |
| **Transfer-appropriate capstones** — produce something real | Every subject ends in a capstone the learner makes or does (built into the Learn-something brief) |

And the floor has a ceiling: what we **refuse**. No seat-time metrics
presented as progress. No engagement-maximization mechanics — the app is on
the learner's side, not competing for their attention. No pretending the
model is infallible: the structure stays human-auditable (§3), mastery
requires the learner to actually produce answers, and the record keeps the
evidence.

---

## 3. The decisions

### D-education-spine. Subject and Topic are new first-class primitives — a per-learner curriculum tree; the doing layer stays on the shared primitives.

A curriculum doesn't fit the existing primitives, and the stretch marks show
exactly where: a Goal's tasks are a flat, day-sized to-do list, but a subject
is a *tree* with structure that matters (strand → topic → micro-topic), state
per node (mastered or not, and when, and how proven), and a lifetime measured
in months of re-visits rather than a burn-down to done. So, on the
Photo/Recipe precedent: **`Subject` joins the primitives** — `belongs_to
:user`, `Visible`, `Sectionable` — with **`Topic`** rows beneath it
(self-referential parent, positioned) carrying the mastery state machine
(§4). Subjects default-tag **Education** but multi-tag like everything else:
music theory is Education + Hobbies, bookkeeping is Education + Career +
Money — the section stays a lens, not a silo (D4).

**The tree is per-learner, never shared reference data.** The skateboarder's
physics tree and the pilot's are different trees on purpose — reordered,
reframed, pruned, extended by the model against this learner's placement and
interests. Two household members studying "the same" subject own two
subjects; comparing them is a household-view concern (§8), not a modelling
one. Per-learner also means private-by-default (D9) with the standard grant
mechanism — a kid's subjects shared to a parent is an explicit, visible
grant, never surveillance ambient in the feature.

**The doing layer is unchanged.** Studying a topic can spawn a Goal broken
into day-sized Tasks (the Learn-something machinery, now aimed at a tree
node), sessions are ToolRuns, recaps and notes are Notes, a finished essay is
a Document, the recital is an Event. The spine holds *what's known*; the
primitives hold *what's happening* — and every existing surface (Today, the
board, the Calendar, the Dashboard) picks the work up unpaid.

### D-curriculum-commons. Core subjects ship as an open, human-readable curriculum library in the repo; enrolling instantiates a personal tree; AI-generated subjects are the same shape through a second door.

"Replace the public school system" cannot mean "the model improvises
K-12 from scratch per household" — coverage would be unauditable and errors
invisible. It also cannot mean bundling someone else's courseware — not
licensable, not editable, not ours. So the skeleton is **plain YAML in the
repo** (`db/curriculum/*.yml`): the **curriculum commons** — core subjects
(numeracy through calculus, reading & writing, the sciences, civics,
financial literacy, digital literacy, health…) as strand → topic outlines
with per-topic summaries stating what mastering it means. Informed by public
standards (Common Core / NGSS and their international cousins) but
jurisdiction-neutral and deliberately terse: an outline a parent can read in
five minutes, diff on GitHub, edit in a text editor, and — eventually —
swap for a community pack, first-party only for now (D11).

**Enrolling instantiates; the model personalizes.** Picking a commons subject
copies the outline into the learner's own `Subject`/`Topic` tree, then a
personalization pass (model, when configured) reframes summaries through the
learner's interest frame, reorders electively, and marks what placement (§6)
says is already known. With no model configured the commons outline *is* the
subject — enrollment, browsing, and manual mastery marking all work dry; the
D20 discipline from day one.

**"Learn anything" is the same shape through a second door.** A free-typed
topic generates a tree instead of copying one — the model drafts the outline,
the learner owns and edits it from there. One schema, two authors; every
downstream feature (mastery, reviews, tutor context, records) is indifferent
to which door a subject came through.

### D-mastery-evidence. Mastery is a per-topic state machine advanced only by evidence — and honest enough to go backwards.

Each topic carries one of five states: **`unseen → learning → practicing →
mastered`**, plus **`rusty`** — the demotion FSRS predicts (§5) when a
mastered topic's reviews lapse past the retention target. Transitions
*forward* happen on evidence only: a passed retrieval check (`quiz_me`), a
tutor checkpoint verdict from a session that actually probed, a teach-back,
or the learner's own say-so for the adult who provably doesn't need to
re-prove arithmetic — self-marking is allowed (their school, their record)
but recorded *as* self-marked. Never on time elapsed, lessons "viewed", or
tasks checked off. Progress anywhere in the UI is the state mix — topics
mastered / practicing / remaining — and pace is measured only against the
learner's **own** optional target date, never an age-grade norm. There are
no letter grades anywhere: a topic is mastered, or not yet.

`rusty` is the state most products refuse to draw, and it's the honest one:
memory decays, and a hub that shows fractions as forever-green while the kid
can no longer do them is lying exactly where it matters most. Mastered means
*maintained* — a rusty topic re-earns green through the same evidence, and
usually needs only minutes.

### D-review-scheduler. Review items are first-class rows scheduled by FSRS; the schedule is arithmetic, the model only writes and grades cards.

Retrieval + spacing is the highest-leverage mechanism in the plan, and it
must work on a box with no model configured, so the split is the D20 one:
**`review_items`** (prompt/answer rows attached to topics, minted by quizzes,
tutor session mining, or by hand) carry FSRS memory state — stability,
difficulty, due date — and the scheduler is **pure deterministic arithmetic**
in `app/services/reviews/`. Self-grading (Again / Hard / Good / Easy) needs
no model at all; a configured model additionally *writes* better cards from
what a session covered and *grades* free-response answers. The daily queue
surfaces everything due across all subjects, interleaved by construction —
ten minutes most days, on a phone, is the habit the whole hub banks on. The
review count on the hub and the `reviews_due` watcher read the same query.

### D-learning-record. The record is the schooling paperwork generated from data the hub already keeps — evidence, never accreditation.

The homeschooling family's blocking artifact isn't the teaching, it's the
*proof*: most jurisdictions want some combination of a portfolio, a
transcript, and an hours log. Everything needed is already in the spine —
mastery transitions are stamped on topics, sessions are logged, capstones
are Documents — plus one small durable table, **`study_logs`** (learner,
subject, date, minutes, activity), written automatically by tutor sessions
and reviews and by hand for offline work, because ToolRuns prune at 90 days
and an hours log must not. Three generator tools (§6) assemble **portfolio**
(curated artifacts + a narrative), **transcript** (subjects, mastery, dates,
capstones), and **hours log** as Documents the household owns, prints, and
files. The app stays jurisdiction-neutral — it produces the evidence; mapping
it to a state's homeschool statute is Q-education-jurisdictions. The framing
is printed on the artifact and non-negotiable: this is a record of
demonstrated work, not a diploma and not accreditation.

---

## 4. Data model

```ruby
create_table :subjects do |t|
  t.references :user, null: false, foreign_key: true
  t.string  :title, null: false
  t.text    :description
  t.string  :commons_key            # curriculum-commons id it was seeded from; nil = generated/custom
  t.text    :interest_frame         # who's learning, through what lens — threads into every prompt
  t.integer :status, null: false, default: 0   # active / paused / finished
  t.date    :target_date            # the learner's own pace anchor; nil = no pace pressure
  t.timestamps
end

create_table :topics do |t|
  t.references :subject, null: false, foreign_key: true
  t.references :parent, foreign_key: { to_table: :topics }   # strand → topic → micro-topic
  t.integer :position, null: false
  t.string  :title, null: false
  t.text    :summary               # what mastering this means — the teaching brief
  t.integer :mastery, null: false, default: 0  # unseen/learning/practicing/mastered/rusty
  t.string  :mastery_evidence      # quiz / tutor / teach_back / self_marked
  t.date    :mastered_on
  t.references :goal, foreign_key: true        # the Learn-something bridge, when studying spawned tasks
  t.timestamps
end

create_table :review_items do |t|
  t.references :user, null: false, foreign_key: true
  t.references :topic, null: false, foreign_key: true
  t.integer  :kind, null: false, default: 0    # flash / free_response / do_this
  t.text     :prompt, null: false
  t.text     :answer
  # FSRS memory state — deterministic scheduler input, nothing else writes these
  t.integer  :state, null: false, default: 0   # new / learning / review / relearning
  t.float    :stability
  t.float    :difficulty
  t.datetime :due_at
  t.integer  :reps, null: false, default: 0
  t.integer  :lapses, null: false, default: 0
  t.datetime :last_reviewed_at
  t.timestamps
end

create_table :study_logs do |t|
  t.references :user, null: false, foreign_key: true
  t.references :subject, foreign_key: true
  t.references :topic, foreign_key: true
  t.date    :on, null: false
  t.integer :minutes, null: false
  t.integer :activity, null: false, default: 0 # tutor / review / lesson / project / other
  t.string  :note
  t.timestamps
end
```

- **`Subject`**: `Visible` + `Sectionable`, default-tagged Education on
  create. Progress is derived, never stored: the state mix over its leaf
  topics.
- **`Topic`**: the tree. Mastery transitions stamp `mastered_on` and
  `mastery_evidence`; demotion to `rusty` clears neither (the history is the
  record). `goal` links the doing layer when a topic is actively being
  worked.
- **`ReviewItem`**: belongs to the learner directly (queue queries never join
  through the tree) and to its topic (evidence and context do).
- **`StudyLog`**: append-only in spirit; the one table the record generators
  (D-learning-record) need that nothing else keeps durably.
- **The commons** is not a table: `db/curriculum/*.yml` read by
  `Curriculum::Commons` (list, show, instantiate). Course files are data
  shipped with the app, versioned in git, editable by the household.
- Visibility everywhere is the standard `Visible` machinery; sharing a
  subject shares its topics, review state, and logs as one grant (the
  container pattern).

---

## 5. The hub, redesigned

The panel follows D37 exactly — `Sections::Panels::Education` + 
`app/views/sections/panels/_education.html.erb`, no shared-file edits — and
the page reads top-to-bottom as *do → continue → begin → oversee → prove*,
phone-first (the top card is the one a thumb reaches for daily). Organic
design language throughout: sand cards on cream, progress in the two ramps
(sage = Education's own color for mastered; terracotta accents for
due/attention), Caprasimo only on the page title.

1. **Today's studying** (lead card). The one-glance answer to "what do I do
   right now": the review-queue button with its due count ("Review — 14 due ·
   ~10 min"), then one resume line per active subject — the exact next topic,
   not the subject name — each a one-tap door into the tutor with everything
   prefilled ("Fractions: comparing with unlike denominators — pick up
   where you left off"). When nothing is due and nothing is active, the card
   collapses to the start-something door. No streak counter; at most an
   honest pacing whisper ("20 focused minutes most days beats three hours on
   Sunday").

2. **Your subjects.** Progress cards: title, a mastery ring segmented by
   state mix (sage for mastered, its tints for practicing/learning, a
   terracotta notch for rusty), current topic, last-studied age, a
   "N reviews due" chip. Tap → the subject page (below). Paused subjects
   sit in a quiet shelf behind a toggle; finished ones move to the record.

3. **Start something new.** Two doors side by side, per D-curriculum-commons:
   **the school shelf** (browse the commons — core subjects with honest
   one-line scopes) and **learn anything** (the free-input door). Beneath
   them, **Suggested for you**: up to three cards from the suggestion engine
   (§7), each carrying its reason in plain sight ("Because of your Theatre
   lens → Public speaking & rhetoric") and a dismiss that sticks.

4. **Household learning** (only when grants exist). One row per household
   member who shares subjects with the viewer: name, their subjects'
   state-mix bars, last session age — the parent's oversight surface,
   existing only where a grant made it exist (D9), linking into the shared
   subject pages.

5. **The record** (quiet, at the bottom). The paperwork drawer: this year's
   hours so far, topics mastered this term, and the three generator tools —
   portfolio, transcript, hours log.

The panel hides the `learn_something` and `tutor` tool cards (it surfaces
both with better context); new tools keep their cards in the Act zone until
the panel absorbs them the same way.

**The subject page** (`/subjects/:id`) is the syllabus made tangible: header
(title, interest frame, the mastery ring, target-date pace line if one is
set), then the topic tree grouped by strand — each topic row a mastery dot +
title + age, with row verbs: **Learn** (tutor, prefilled with the topic and
its context), **Quiz me** (the mastery gate), and the honest **Mark
mastered** (recorded as self-marked). The capstone sits at the end of the
tree as its own card. Below: the standard sharing card, the subject's study
log strip, edit/pause/finish. The tree is editable — add, reorder, prune;
it's the learner's curriculum, not ours.

**The review session** (`/reviews`) is a full-screen, card-at-a-time flow
built for a phone held one-handed: prompt → reveal → Again/Hard/Good/Easy
(the FSRS quartet). Every kind self-grades in v1 — free-response against
"what you'd have accepted from a student", do-this by doing it — with
model grading of typed answers a W6 nicety, never a dependency.
Ten minutes, interleaved across subjects, ends with what moved: "3 topics
shored up, 11 items pushed out past next month."

---

## 6. The tools

Upgrades to the two that exist, then the new slate. Every tool follows the
D19 contract; chat tools ride ChatBase (D29).

- **`learn_something`** (upgrade). The plan tool becomes the enrollment door:
  it creates a `Subject` with a generated tree (or routes to the commons when
  the topic matches one), sets the interest frame from the angle input, and
  still spawns the first paced Goal→Tasks so Today keeps pulling the learner
  back. Existing runs and goals are untouched.
- **`tutor`** (upgrade). Becomes curriculum-aware: entered from a topic row it
  knows the topic, its strand, the learner's mastery states around it, and
  past recaps; session end gains two moves — a **checkpoint verdict** (the
  session probed; the tutor proposes advancing the topic's state, the learner
  confirms) and **session mining** (mint 2–4 review items from what was
  actually covered). Both are proposals in the transcript, never silent
  writes. A session also writes its `study_log` row.
- **`placement`** (new, chat). "Find my edge": a short adaptive conversation
  per subject — a few questions per strand, harder until they miss — that
  stamps initial mastery so the returning adult starts algebra at algebra,
  not at counting. Placement marks are evidence-typed as placement, and
  generous by design: mastery can always be re-proven later; boredom in week
  one is the killer.
- **`quiz_me`** (new, chat). The retrieval gate on one topic: a handful of
  questions from the topic summary and its review items, graded in
  conversation, verdict proposed at the end. Passing is what `practicing →
  mastered` means; the misses mint review items aimed at the gap.
- **`quiz_note`** (new, chat — D-note-quiz). The same gate, pointed outside
  the syllabus: any Note carries a **Quiz me on this** button, bound to the
  note through `tool_runs.subject` rather than a form input. A note a quiz
  filed is a report card, not material, so a quiz on one points past itself
  at the topic and the cards the earlier quiz minted — and finishing it makes
  the same three writes `quiz_me` does, through the same helpers.
- **`explain_this`** (new, chat). The homework-tonight door, deliberately
  outside the curriculum spine: paste anything — the worksheet question, the
  confusing paragraph — get it explained at your level, Socratic rules in
  force (guided, never done). No subject required; offers to file what it
  taught into one when the learner has a matching tree. (A photo of the
  worksheet is the vision-toggle tier, later.)
- **`progress_report`** (new). The D-learning-record generators: portfolio,
  transcript, hours log — pick the learner (self, or a subject shared to
  you), the date range, the artifact; out comes a Document. Deterministic
  assembly from the spine and `study_logs`; the model, when present, writes
  the narrative paragraphs only.

The review queue is a surface, not a tool: scheduling is arithmetic (D20),
and a daily habit shouldn't cost a tool-run ceremony.

---

## 7. Personalization, and the suggestion engine

Two distinct mechanisms share the word "personalized"; the plan keeps them
named apart:

**Suggested subjects** (what to learn). Deterministic candidates first, model
phrasing second — the D20 watcher discipline. The candidate pass reads what
the lens model already holds: hobby lenses, Career signals (a job-search
goal, a title in the resume), Money situations (a debt-payoff plan suggests
financial literacy), People (a kid's grade-adjacent commons subjects). A
static affinity map in the repo (hobby → subjects: theatre → public
speaking, rhetoric; skateboarding → physics of motion, filmmaking; gardening
→ botany, soil chemistry…) makes the common cases free and auditable; the
model, when configured, extends it to lenses the map doesn't know. Cards
always carry their reason, dismissals stick, and nothing auto-enrolls — the
agent proposes, the learner disposes (D20).

**Interest framing** (how it's taught). The subject's `interest_frame` — who
this learner is, what they love, what register to teach in — threads into
every downstream prompt: tree personalization, tutor sessions, quiz
questions, review-card generation. Fractions through recipe scaling for the
cook, through gear ratios for the cyclist. The caveat is structural, not
aspirational: framing tunes *presentation*; advancement still gates on
retrieval evidence, so charm can't fake mastery.

**Watchers** (all deterministic signals, D20):

- `reviews_due` — the queue crossed a threshold or is going stale → one
  suggestion, throttled, with the ten-minute honest estimate.
- `subject_stall` — an active subject untouched N days → re-entry card
  naming the exact resume point (the goal_stall pattern; re-entry cost is
  what kills self-paced learning, so the card's whole job is making resuming
  one tap).
- `rusty_radar` — mastered topics decayed → "15 minutes shores up fractions
  and percentages."
- `pace_check` — only for subjects with a target date: ahead/behind, computed
  honestly, phrased kindly.
- `weekly_digest` — the household's learning week on the Dashboard: sessions,
  topics moved, what's due next week. Reads grants like everything else.

---

## 8. Households: kids, parents, and privacy

Learners are **household Users** — real accounts, real ownership, kids
included. No shadow "learner profiles": a profile that isn't a user would
need its own parallel visibility, sharing, and auth story, and the payoff
(no login for a 7-year-old) is smaller than the cost of two ownership
models. A young kid's device can stay logged in; the account is still theirs
and grows up with them — the record of learning to read belongs to the person
who learned to read.

Privacy is the standard machinery, stated plainly for this hub because the
temptation to make oversight ambient is strongest where kids are involved:
**a parent sees a kid's learning only through explicit grants** (per-subject,
or share-everything-in-Education), visible in the kid's own sharing UI like
any grant (D9). What a family *should* grant is theirs to decide; the
household card (§5) renders exactly what grants exist and nothing more.
Tutor transcripts are ToolRuns and prune like all ToolRuns — the durable
record is recaps, mastery, and logs, which is also the least-surveillant
sufficient record.

Shared subjects open the co-learning door later (two members, one dinner-table
subject, compared progress *by consent*) — designed never to become a
leaderboard by default.

---

## 9. Build waves

Each wave lands green (`bin/rails test`, `bin/rubocop`) and is independently
shippable; the order front-loads the spine because every later wave hangs off
its shape.

| Wave | Contents | Status |
|---|---|---|
| **W1 — the spine** | `subjects` + `topics`, models + `Visible`/`Sectionable`, the commons v1 (`Curriculum::Commons` + ~6 course files: arithmetic→algebra, reading & writing, one science, civics, financial literacy, digital literacy), enroll + generated-tree doors, subject CRUD + the syllabus page with manual mastery marking, `learn_something` upgrade, hub panel v1 (subjects · start-new · resume strip) | ✅ built |
| **W2 — mastery earns its keep** | The evidence state machine, `quiz_me`, `placement`, tutor curriculum-context + checkpoint verdicts + session mining (items stored inert until W3 schedules them), `study_logs` written by sessions | ✅ built |
| **W3 — the review engine** | `review_items` live: the FSRS scheduler service + its unit-test battery, the `/reviews` session surface, the queue on the hub, interleaving, `rusty` demotion, `reviews_due` watcher | ✅ built |
| **W4 — personalization** | The suggestion engine (affinity map + lens candidates + model extension), suggested-subject cards, interest framing threaded through every prompt, `subject_stall` / `rusty_radar` / `pace_check` watchers, weekly digest | ✅ built |
| **W5 — household + the record** | Subject sharing polish (container grant), the household card, `progress_report` (portfolio · transcript · hours), the record drawer, `explain_this` | ✅ built |
| **W6 — the horizon** | Vision (photo of the worksheet / the handwritten page), voice sessions, commons pack format for community curricula (behind D11), co-learning, offline-friendly review, standardized-practice-test import (Q-education-assessment-trust) | horizon |

W1 alone is already a better hub than the placeholder: an owned curriculum
you can walk through with the existing tutor is the Organize mode for
learning. W1–W3 are the two-sigma core — mastery pacing + 1:1 tutoring +
spaced retrieval — and everything after is leverage on top of it.

---

## 10. Open questions

- **Q-education-jurisdictions.** Homeschool law is a 50-state (and
  multi-country) matrix of notification, hours, subjects, and assessment
  requirements. The record generators stay jurisdiction-neutral; a per-state
  requirements table is a *dataset* (the `datasets` service shape), not
  code, and worth shipping only when it can be maintained honestly. Until
  then the app produces evidence and the household maps it to their law.
- **Q-education-assessment-trust.** Self-graded and model-graded mastery is
  right for learning (low stakes, fast feedback) — but when the record
  matters externally, does the household want calibration against something
  the model didn't grade? Likely shape: import scored standardized practice
  tests as Documents linked to subjects — external anchors, owned like
  everything else. Decide after real use.
- **Q-education-materials.** Text and conversation are v1's media, and the
  commons carries no external links yet. Should topic entries cite open
  materials (OpenStax, Khan Academy, LibreTexts, Project Gutenberg) as
  *reading lists* — curated URLs in the YAML, no scraping, no bundling?
  Probably yes and probably W4-adjacent; the licensing and link-rot story
  needs an hour of thought first.
- **Q-education-fsrs-tuning.** FSRS ships default parameters; per-learner
  optimization needs hundreds of reviews of history. Start with defaults +
  a per-learner desired-retention setting (0.9 default), revisit optimization
  when real review histories exist to fit against.
