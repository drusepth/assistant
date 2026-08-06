# CLAUDE.md

## What this project is

An **open-source, self-hostable AI life assistant** — a Rails 8.1 website anyone can run at home. The goal: democratize AI assistance from the bottom up, so that the productivity and life-navigation benefits of AI are *owned* by ordinary people rather than rented from a few large companies.

We are NOT building or integrating specific models. The app is **model-agnostic**: an open configuration layer lets the user plug in whatever remote (or, later, local) model they choose. We build everything *around* the model.

## Mission (the "why")

- If AI capability ends up as something people **rent from a few landlords**, the productivity windfall concentrates and the feudal endgame becomes structurally likely.
- Policies can be repealed; **widely-deployed, ownerless infrastructure cannot**. Code replicates at zero cost — one builder can ship a protocol that millions run (Linux/Signal/BitTorrent pattern).
- The counter-move is lowering the floor of *ownership*: local-first tooling that gives the 99% the service stack the wealthy already get from executive assistants, accountants, lawyers, and tutors.
- Target user is explicitly **the 99% who don't have those professionals** — not power users, not enterprises.

Design implications: local-first, self-hostable, open source; the user owns their data (the memory/context layer is the durable asset; models are swappable commodities); adoption beats elegance (one-command install is a feature); community-extensible eventually (packs are first-party only for now — see D11).

## Product structure (FINALIZED — do not redesign without asking)

### Sections (top-level, user-toggleable on/off; FTUE will pick defaults)

1. **Health**
2. **Hobbies**
3. **Education**
4. **Career**
5. **People** — friends, family, communities, church, clubs, meetups
6. **Money** — subsections: Budget, Debt, Taxes, Assets, Bills, Subscriptions, Benefits
7. **Rights** — subsections: Immigration, Renting, Voting, Disputes

Sections live in a database taxonomy table (`sections`, self-referential parent for subsections), not code enums.

### Data model: lens-over-primitives (KEY ARCHITECTURAL DECISION)

Sections are **lenses, not silos**. ONE shared pool of primitives; sections are tags/filters over it (polymorphic `section_taggings` join). Sections never own their own tables.

Primitives (each `belongs_to :user`, includes `Sectionable` + `Visible`):
- **Event** — dated things (appointments, deadlines, renewals)
- **Task** — day-sized doable things with a clear done/not-done state; board-viewable (Later/Today/Done)
- **Document** — files with understanding (Active Storage attachment + extracted text + AI summary)
- **Person** — contacts and what matters about them (optionally linked to a household User)
- **Goal** — high-level outcomes ("get a job") AI-broken into day-sized Tasks (D17); lives inside the Tasks section; Situations are Goals spawning multi-tagged Tasks/Events
- **Note** — everything the assistant knows about the user

Every item is **multi-taggable** by section (e.g., "Mom's cardiology appointment" = Health + People).

### Households, users, and privacy

- **Household multi-tenancy**: one instance serves a household; each member is an independent user (Rails 8 built-in auth).
- **Private by default**: items are invisible to other household members until shared via `access_grants` — per-item, or per-section ("share all my Money items with my spouse").
- **No moral/ethical judgments baked in**: access control is visible, user-controlled configuration — never hidden defaults. See D9.
- Cross-user AI features (e.g., coordinating two spouses' appointments) operate only over what's shared with the requesting user.

### Views (cross-section lenses; fall out of the data model for free)

- **Dashboard** — AI synthesis across enabled sections ("3 things need attention this week")
- **Calendar** — all Events, any tag; the flagship holistic view
- **Today/Inbox** — all tasks + upcoming events
- **Documents vault** — all docs, filterable by section
- **Tasks board** — one merged Tasks section (D17): goal-capture input → AI breakdown, goals progress strip, Later/Today/Done task kanban
- **Settings** — section toggles, per-section agent dials
- **FTUE** (future) — asks which sections to default on

### The three modes (canonical product thesis)

1. **Organize** (passive) — owned repository of your life; valuable with zero AI. Built first.
2. **Tools** (self-serve) — "find in-network cardiologists," "draft this appeal letter." First-party workflow packs plug in here.
3. **Agent** (proactive) — app comes to the user. Built last; per-section aggressiveness dials.

### Model integration

Single **OpenAI-compatible chat-completions adapter** behind a provider picker in Settings: OpenAI (key + model), Chroma Golem (key only; router-style), or a custom endpoint (any OpenAI-compatible base URL — Ollama, OpenRouter, Groq). Remote models first; local models are a custom-endpoint config swap. Security/encryption hardening deliberately deferred until the foundation is built.

## Tech stack

Rails 8.1 · Ruby 3.3 · SQLite · Solid Queue/Cache/Cable · Hotwire (Turbo + Stimulus) · Propshaft + importmaps · Minitest + fixtures · Kamal + Dockerfile. Run tests with `bin/rails test`; lint with `bin/rubocop`.

## Design system

Tailwind CSS v4 (standalone binary, no Node) + ViewComponent + a default `ApplicationFormBuilder`. Four redesign-in-one-place layers: tokens (`app/assets/tailwind/application.css` `@theme`), atoms (`.btn`, `.input`, `.card`, `.chip` in the same file), `Ui::` components (`app/components/ui/`), and per-primitive row partials (`tasks/_task`, …). Views never hand-roll buttons/inputs/cards. See `docs/DESIGN.md`.

## Docs

- `docs/VISION.md` — full mission background and strategic reasoning
- `docs/PRODUCT.md` — detailed section-by-section feature brainstorm
- `docs/DECISIONS.md` — decision log + open questions
- `docs/ROADMAP.md` — Milestones 2 (Tools) & 3 (Agent) design: section page anatomy, tool pipeline, agent/suggestion architecture (D18–D20)
- `docs/ARCHITECTURE.md` — schema, visibility model, adapter design, build sequence
- `docs/DESIGN.md` — design language: tokens, atoms, components, conventions

## Where we left off

**Milestone 1 (Organize core, AI-lite — D13) is complete** and under test: the database layer (households/users/sessions, seeded sections taxonomy, six primitives, tagging, access grants with `visible_to`), the design system, the full Organize UI — CRUD for all six primitives, Dashboard, Today, Calendar, Documents vault (section filters), Goals boards (kanban), section pages, Settings (section toggles + section-level sharing), item-level sharing on every show page — onboarding/member management (D15: first-run `/setup`, link-based invitations, admin roles), and the one AI feature: document understanding (household `ModelProfile` configured in Settings → `Llm::Client` OpenAI-compatible adapter → `AnalyzeDocumentJob` → summary + section tags, auto-applied to untagged documents, suggest-and-click otherwise). **Capture is now zero-friction (D16)**: every primitive's new form is minimal (task = title, event = title + day, note = body, goal = title, person = name, document = file) and a per-primitive `Categorize*Job` auto-files sections plus implied dates/times/titles/relationships; date fields everywhere use the native picker + shortcut chips, and event forms use date + time parts (blank start time = all-day) instead of raw datetimes. **Tasks and Goals are now one section (D17)**: the Tasks page leads with a goal-capture input ("What do you want to accomplish?") → `BreakDownGoalJob` (one LLM call replacing `CategorizeGoalJob`) auto-creates 3–10 scheduled, section-tagged day-sized tasks and files the goal; below it a goals progress strip, then the Later/Today/Done task kanban (Today = pulled-in ∪ due/overdue; Done derived from `completed_at`). Goals lost their board and `backlog` status (active/done, auto-finish when the last step completes); goal pages have "suggest more steps" (append-only); task cards/rows show their goal as a flag chip; dashboard header has +Task/+Event/+Goal. **People has modular address-book import**: `People::Import` (parser registry — vCard 2.1/3.0/4.0, Google CSV, Outlook CSV, generic CSV fallback) normalizes contacts (multi-valued phones/emails/addresses; overflow lands in notes so nothing is dropped), dedupes by name, tags imports with the People section directly (no per-contact LLM calls), and `Person` gained an `address` column; UI at /people/import/new, linked from the People index; on supported mobile browsers (Chrome/Edge/Samsung on Android) the same page also offers pick-straight-from-the-phone via the Contact Picker API (Stimulus `contact-picker` controller serializes picks to JSON → `DeviceJson` parser, same pipeline, hidden where unsupported). Adding a format = one parser class in `app/services/people/import/`. **Calendar has the same modular import**: `Events::Import` (parser registry — RFC 5545 iCalendar covering Google/Apple/Outlook/feeds with TZID/UTC/floating times, exclusive all-day DTENDs, DURATION, cancelled events, and recurrence expanded into concrete events within a 1-month-back/12-months-ahead window honoring EXDATE and RECURRENCE-ID overrides, exotic rules kept as first occurrence + "Repeats:" note; Outlook calendar CSV; generic CSV fallback) dedupes by title + start time, folds organizers/links/categories into descriptions so nothing is dropped, and deliberately leaves imports untagged with no per-event LLM calls (Calendar shows all events regardless of section); UI at /events/import/new, linked from the Calendar header. Adding a format = one parser class in `app/services/events/import/`. **Milestones 2 (Tools) and 3 (Agent) are designed** — see `docs/ROADMAP.md` (D18–D20): section pages become Act/Attend/Browse zones; a Tool is a first-party context→LLM→draft-primitives pipeline (plan tools ride D17 breakdown, and Situations are plan tools, so Q7's eviction test rides this infra); the agent writes only to a `suggestions` table fed by deterministic watchers, with Off/Quiet/Active per-section dials. **M2.1 (Tools foundation) is built**: section pages lead with an Act zone of tool cards (`Tool.for_section`, subsection tools surface on the parent too) and the empty state is now tool cards + quick capture pre-tagged with the section (hidden fields through the minimal forms; hand-tagging keeps auto-sort away per D16); tools are declarative classes (`app/tools/`, `Tool::Base` DSL: title/sections/kind/inputs/prompt, explicit `Tool::SLUGS` registry per D11); a run is a `ToolRun` row (inputs/status/error + `tool_run_items` join to created primitives) driven by `ToolRunJob` with a Turbo-refreshing show page that doubles as history; the first tool is **Draft a dispute letter** (Rights → Disputes: picks a vault document, drafts a formal letter as a filed Note + up to 3 follow-up Tasks, filed under the tool's sections ∪ the document's). **M2.2 (first plan tool) is built**: "Learn something" (Education) proves the plan half of D19 with zero new schema — a plan tool is goal capture with framing (creates a plain Goal, hands it to the shared `Goals::BreakDown` with an optional `brief` injected into the one prompt; `plan!` = call + apply, extracted from `BreakDownGoalJob` and shared by both); a failed run leaves an ordinary retryable goal. Eviction was deprioritized (low-frequency, narrow) — Situations are now M2.4, "moving" first (that's the Q7 cross-section test), eviction on demand. Next steps, in order:
1. **M2.3** — coverage slate: doctor-visit prep, cancel-subscription, reconnect (each is one declarative class now)
2. **M2.4** — Situations as plan tools with rich cross-section briefs: "moving" first
3. Then Milestone 3 per the roadmap (suggestions core → dials + watchers → digest); D14 leftovers (export, `model_profiles.api_key` encryption) slot in anywhere
