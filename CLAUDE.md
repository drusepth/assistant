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

- `docs/STATUS.md` + `docs/status/` — build log: what is built so far, and what is next (start here; `bin/status` prints both in order)
- `docs/VISION.md` — full mission background and strategic reasoning
- `docs/PRODUCT.md` — detailed section-by-section feature brainstorm
- `docs/DECISIONS.md` — decision log + open questions
- `docs/ROADMAP.md` — Milestones 2 (Tools) & 3 (Agent) design: section page anatomy, tool pipeline, agent/suggestion architecture (D18–D20)
- `docs/TOOLS_PLAN.md` — the high-impact tool wave: nine tools in five waves, per-tool specs, the three infra seams (shared draft plumbing, `next_tools` routing (D28), chat tools (D29))
- `docs/PHOTOS_PLAN.md` — household photos: the Photo primitive, albums, sharing, and the S3-compatible storage seam (D-photos-primitive, D-storage-seam)
- `docs/EMAIL_PLAN.md` — email import & monitoring: the mirror layer (D-mirror-layer) in its own database (D-mirror-database), multi-account IMAP sync, triage + sender-rule feedback loop, digest/urgent alerts, the boomerang family (D-email-monitoring), the hostile-input threat model
- `docs/RECIPES_PLAN.md` — the recipe box: the Recipe primitive and its ingredient parser, recipe books, sharing to the household and to people outside it by link, and the pantry/AI waves (D-recipe-primitive, D-share-link, D-pantry)
- `docs/PASSWORDS_PLAN.md` — the password vault: per-user envelope encryption, sharing, TOTP, import/export, and the agent-access bridge (D-passwords-vault, D-vault-crypto)
- `docs/ARCHITECTURE.md` — schema, visibility model, adapter design, build sequence
- `docs/DESIGN.md` — design language: tokens, atoms, components, conventions

## Where we left off

Read the build log with `bin/status` — `docs/STATUS.md` (the log through
August 2026) followed by `docs/status/`, one file per entry after that.

It lives outside this file on purpose. The log changes on nearly every branch,
and while it lived here it made CLAUDE.md the most conflict-prone file in the
repo — then it made `STATUS.md` the most conflict-prone file in the repo.
**Record your milestone by adding a new file** —
`docs/status/YYYY-MM-DD-kebab-slug.md`, one entry, nothing else in it; see
`docs/status/README.md`. Never append to `docs/STATUS.md`.

## Parallel branches: conflict hygiene

Several branches land concurrently, so a few rules for the shared files and
global sequences:

- **New decisions get slug IDs, not sequence numbers.** Two in-flight branches
  can't see each other's claims, so a shared counter guarantees collisions (the
  D30 photos/task-chat clash cost a ~20-file renumber). New entries in
  `docs/DECISIONS.md` are `**D-kebab-slug.**` (e.g. `**D-photos-primitive.**`) —
  self-describing, greppable via the `D-` prefix, collision-proof. D1–D37 keep
  their numbers; never renumber them. If something truly needs a sequential
  claim, reserve it by pushing a one-line stub to main *first* (e.g.
  `**D33. (reserved: topic — see PR #NN.)**`), before any branch references it.
- **Migration timestamps are claimed at generation time**: always create
  migrations with `bin/rails g migration` so they carry real second-resolution
  timestamps — never hand-rounded ones like `…180000`.
- **Registry hub files conflict by design; that's fine.** Lists everyone
  appends to (`ICON_PATHS`, `routes.rb`, `User` has_many, `Tool::SLUGS`,
  fixture files) merge with a trivial keep-both — resolve, don't redesign.
  (`docs/DECISIONS.md` stays on the default strategy on purpose: its
  conflicts are what force the D-number re-check above.)
  `db/schema.rb` is never hand-merged: run `bin/resolve-schema` during the
  merge — it takes the incoming copy and re-runs `bin/rails db:migrate` so
  the file regenerates with both branches' migrations.
- **Section pages are extension points, not shared files (D37).** Building
  out a section = adding `Sections::Panels::<Slug>` (panel data + hidden
  tool cards) and `app/views/sections/panels/_<slug>.html.erb`, plus your
  own `app/services/<slug>/`, tools, and watchers. Never edit
  `SectionsController`, `sections/show.html.erb`, or `SectionsHelper` for
  a section feature — those three were the merge hot spot when the
  Hobbies, subsection-tile, and Health buildouts landed in parallel.
  Merge `origin/main` into your branch early and often; small frequent
  merges beat one big one.
- **Append-only logs append *files*, not lines.** The build log was the
  standing counter-example: `merge=union` on `docs/STATUS.md` made `git merge`
  keep both branches' lines, but GitHub computes PR mergeability without
  applying `.gitattributes`, so every parallel branch still *showed* a STATUS
  conflict that only a local merge could clear. Entries now live one per file
  under `docs/status/` (`YYYY-MM-DD-kebab-slug.md`, see its README), so two
  branches logging the same week share no line in any file and there is
  nothing for any tool to conflict over. Reach for the same shape whenever a
  list only ever grows and order is the only relationship between items.
