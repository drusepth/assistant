# PRODUCT.md

Detailed product design. Structure is finalized (see CLAUDE.md); feature lists below are brainstorm-level and expected to evolve.

## The three modes (applies to every section)

| Mode | Direction | Example |
|---|---|---|
| **Organize** | Passive repository | Store the lease, track the appointment, remember the deadline |
| **Tools** | User-initiated, self-serve | "Find in-network cardiologists," "draft this appeal letter" |
| **Agent** | Proactive, app-initiated | "You're due for a physical — want me to find slots?" |

Build order and trust ladder: Organize → Tools → Agent. Agent aggressiveness is a per-section user setting.

## Sections

### 1. Health
- Symptom journaling; medication tracking
- Doctor-visit prep (question lists, history summaries)
- Test results / diagnosis comprehension in plain language (**preparation and comprehension, not diagnosis** — carefully scoped)
- Find providers in insurance coverage
- Checkup/screening cadence tracking → Calendar
- Mental health check-ins
- Note: medical *billing disputes* live in Rights → Disputes; care itself lives here.
- Full section deep-dive in `docs/HEALTH.md`: the care radar (per-kind checkup tracking), the insurance stack (find-care, explainer, plan comparison), Mind (check-in chat, calm practices, find-a-therapist — support, not therapy), the data-source survey, and the later rungs (medications, symptom journal, wearables).

### 2. Hobbies
- Project tracking for creative work, side builds, collections
- Skill progression and practice scheduling
- Purpose & creation focus: in a post-labor transition, meaning-making grows in importance. Goal decomposition into trackable steps (PASS-style).
- Full section deep-dive in `docs/HOBBIES.md`: hobbies as user-created sub-lenses (Q11), a tool slate (start-a-hobby, project ideas, find-your-people), and the neglected-hobby watcher.

### 3. Education
- Infinite patient 1:1 tutoring for user and kids, adapted to level and language
- Homework help; "explain anything at my level"
- Reskilling and career-transition learning paths
- Example pack: "IEP meeting prep"

### 4. Career
- Job search + matching; resume and interview prep
- Workplace rights awareness (wage theft, misclassification, unsafe conditions — overlaps Rights)
- **Small-business-in-a-box** for the self-employed: invoicing, bookkeeping categorization, marketing copy, customer replies, basic legal templates. Lets a plumber or a co-op capture the AI productivity windfall themselves.
- Full section deep-dive in `docs/CAREER.md`: the career-signal ladder (granted data — pay-stub extraction, LinkedIn export, email — over a manual floor, D-career-signal), the tool slate (interview prep/mock, application tailor, pay-stub check, raise case, offer decode, lost-my-job Situation, next-move counselor), the watcher slate (raise cadence + real-terms drift + stub anomaly), and and the external-data layer — public wage/CPI datasets, the job scout, ask-then-send applications (D-public-datasets, D-career-web).

### 5. People
Friends, family, communities, church, clubs, meetups.
- Staying in touch; remembering what matters to each person
- Event planning; caregiving coordination; co-parenting logistics
- Community layer: mutual aid, neighborhood organizing, co-op tooling — an assistant that only optimizes individuals recreates atomization; collective capacity is part of the thesis.
- Full section deep-dive in `docs/PEOPLE.md`: the roster/dashboard split (D-people-dashboard — Address Book = CRM, section page = social dashboard over the kept-in-touch circle), a tool slate (what-do-I-say chat, get-together planner, gift ideas, make-new-friends), birthday radar, and groups as sub-lenses.

### 6. Money
Subsections: **Budget, Debt, Taxes, Assets, Bills, Subscriptions, Benefits**
- Budget: cash-flow tracking and refinement (flow is the daily battle for the target user; assets are the goal)
- Debt: payoff strategy
- Taxes: prep, deadline tracking, self-employment complexity
- Assets: savings/investment tracking as users climb the ladder
- Bills: recurring obligations, renewal dates, price-hike detection
- Subscriptions: audit, "cancel this for me" drafting
- Benefits: eligibility discovery (billions go unclaimed because people don't know they qualify), application navigation — SNAP, Medicaid, unemployment, disability. *(Open question: could move to Rights.)*

### 7. Rights
Subsections: **Immigration, Renting, Voting, Disputes**
The advocate stack — the mission's heart. Ordinary people lose money and wellbeing to asymmetries of expertise; the wealthy have professionals for this.
- Immigration: paperwork navigation, deadline tracking
- Renting: lease review before signing, landlord issues, security deposit recovery, eviction response
- Voting: registration, deadlines, ballot information
- Disputes: medical bill disputes, insurance denials/appeals, debt collectors, warranty fights, small claims — document understanding + formal letter drafting + deadline tracking
- Mostly workflow design rather than frontier model capability — high impact per engineering hour.

## Primitives (shared pool; sections are lenses/tags over these)

- **Events** — dated (appointments, deadlines, renewals)
- **Tasks** — doable, optional dates
- **Documents** — files with understanding (lease, test results, resume, tax forms)
- **People** — contacts + context
- **Goals/Projects** — multi-step with progress; kanban-viewable
- **Notes/Memory** — the assistant's knowledge of the user

All primitives are multi-taggable across sections.

## Views

- **Dashboard** — AI synthesis across enabled sections; "what needs attention." The app *comes to you* here.
- **Calendar** — all Events regardless of tag. Health checkups, career deadlines, debt payments, renewals in one place.
- **Today/Inbox** — tasks + near-term events
- **Documents vault** — all documents, filterable by section
- **Goals boards** — kanban
- **Settings** — section toggles, per-section agent dials
- **FTUE** (future) — asks which sections to default on; a 22-year-old renter and a 60-year-old caregiver should see different apps.

UX thesis: sections are where you *go deep* (pull); Dashboard/Calendar/Today are where the app *comes to you* (push).

## Situations (first-class cross-cutting concept)

Life events span sections: "I lost my job" = Career + Money + Benefits + Health(insurance). Modeled as a Goal that spawns Tasks/Events tagged across sections, all surfacing in the shared views. Flagship experiences will likely be situations, not sections.

Candidate launch situations: lost my job · eviction notice · new baby · new diagnosis · moving · starting a business.

## Horizontals

- **Owned memory layer** — local, portable, inspectable; any model plugs into it. The moat.
- **Voice-first** — local STT/TTS.
- **Workflow packs** — community bundles namespaced by section.
- **Household multi-user** — one instance, one family.
- **One-command install** — a launch-blocking feature, not polish.
