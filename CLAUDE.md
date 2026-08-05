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
- **Task** — doable things, optional dates
- **Document** — files with understanding (Active Storage attachment + extracted text + AI summary)
- **Person** — contacts and what matters about them (optionally linked to a household User)
- **Goal** — multi-step things with progress; kanban-viewable; Situations are Goals spawning multi-tagged Tasks/Events
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
- **Goals boards** — kanban
- **Settings** — section toggles, per-section agent dials
- **FTUE** (future) — asks which sections to default on

### The three modes (canonical product thesis)

1. **Organize** (passive) — owned repository of your life; valuable with zero AI. Built first.
2. **Tools** (self-serve) — "find in-network cardiologists," "draft this appeal letter." First-party workflow packs plug in here.
3. **Agent** (proactive) — app comes to the user. Built last; per-section aggressiveness dials.

### Model integration

Single **OpenAI-compatible chat-completions adapter** (configurable base URL + key + model name). Remote models first; local models (Ollama, llama.cpp, LM Studio) become a config swap later. Security/encryption hardening deliberately deferred until the foundation is built.

## Tech stack

Rails 8.1 · Ruby 3.3 · SQLite · Solid Queue/Cache/Cable · Hotwire (Turbo + Stimulus) · Propshaft + importmaps · Minitest + fixtures · Kamal + Dockerfile. Run tests with `bin/rails test`; lint with `bin/rubocop`.

## Docs

- `docs/VISION.md` — full mission background and strategic reasoning
- `docs/PRODUCT.md` — detailed section-by-section feature brainstorm
- `docs/DECISIONS.md` — decision log + open questions (D1–D14)
- `docs/ARCHITECTURE.md` — schema, visibility model, adapter design, build sequence

## Where we left off

Milestone 1 is **Organize core, AI-lite** (see D13). The database layer is built: households/users/sessions, sections taxonomy (seeded), six primitives, section tagging, access grants with the `visible_to` scope, all under test. Next steps, in order:
1. Controllers/views for the primitives + the cross-cutting views (Calendar, Today, Vault, Boards, Dashboard shell)
2. Settings (section toggles)
3. The one AI feature: document upload → extraction → summary + suggested tags (Solid Queue job through the OpenAI-compatible adapter; `model_profiles` table arrives with this)
4. Then: pressure-test Situations with "eviction notice" (Q7)
