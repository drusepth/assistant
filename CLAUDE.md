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
8. **Travel** — added after the original seven (D-travel-facet); a hub whose first panel is the geotagged-photo world map. `docs/TRAVEL.md`

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

Single **OpenAI-compatible chat-completions adapter** behind a provider picker in Settings: OpenAI, Anthropic (Claude), and Google (Gemini) — each an API key + model name, the latter two over the providers' own OpenAI-compatibility endpoints — plus Chroma Golem (key only; router-style) and a custom endpoint (any OpenAI-compatible base URL — Ollama, OpenRouter, Groq). Presets may carry per-provider quirks the adapter absorbs (`json_mode:`, `max_tokens:`) but never a second code path (D-provider-presets). **Local models are the recommended answer and the UI argues for them** — an `allow_cloud_models` toggle (default on) gates every `cloud: true` preset, and the picker groups self-run endpoints ahead of hosted ones (D-local-first-models). Local models work today through the self-hosted endpoint (Ollama, llama.cpp, LM Studio); first-class one-click local setup is still to come. Security/encryption hardening deliberately deferred until the foundation is built.

## One standing rule about classification

**Keyword and pattern matching is never how this app decides what something
*is*** (D-no-keyword-logic). When the question is "what is this about", the
model classifies — batched, over a bounded set, validated into a closed set of
rows we already have. Make it affordable by asking about *less*, never by
swapping in a cheaper mechanism that answers a different question. With no
model configured, such a feature is off and says so rather than guessing. This
does not touch deterministic work (parsing, dates, arithmetic, search, or the
user's own explicit rules).

## Tech stack

Rails 8.1 · Ruby 3.3 · SQLite · Solid Queue/Cache/Cable · Hotwire (Turbo + Stimulus) · Propshaft + importmaps · Minitest + fixtures · Kamal + Dockerfile. Run tests with `bin/rails test`; lint with `bin/rubocop`.

## Design system

Tailwind CSS v4 (standalone binary, no Node) + ViewComponent + a default `ApplicationFormBuilder`. Four redesign-in-one-place layers: tokens (`app/assets/tailwind/application.css` `@theme`), atoms (`.btn`, `.input`, `.card`, `.chip` in the same file), `Ui::` components (`app/components/ui/`), and per-primitive row partials (`tasks/_task`, …). Views never hand-roll buttons/inputs/cards. See `docs/DESIGN.md`.

## Docs

- `docs/STATUS.md` — what is next, and the front door to the build log in `docs/status/` (one file per entry; read it with `bin/status`) (start here)
- `docs/VISION.md` — full mission background and strategic reasoning
- `docs/PRODUCT.md` — detailed section-by-section feature brainstorm
- `docs/DECISIONS.md` — the front door to the decision log in `docs/decisions/` (one file per entry, named by its ID; read it with `bin/decisions`)
- `docs/ROADMAP.md` — Milestones 2 (Tools) & 3 (Agent) design: section page anatomy, tool pipeline, agent/suggestion architecture (D18–D20)
- `docs/TOOLS_PLAN.md` — the high-impact tool wave: nine tools in five waves, per-tool specs, the three infra seams (shared draft plumbing, `next_tools` routing (D28), chat tools (D29))
- `docs/AGENT_PLAN.md` — the active agent: what "Active" buys beyond a daily cadence — suggestions that retire when the world resolves them (D-suggestion-lifecycle), dial-gated budgeted preparation that parks a finished draft on the suggestion and lands nothing until the click (D-agent-prepared-work), the signed decision link that closes the notification loop on the phone (D-decision-links), and the agent offering its own dial tuning, up and down (D-agent-earned-dials)
- `docs/PEOPLE_CIRCLES.md` — the People page redesign: groups and the circle as one grid of one card (avatar stacks, one line of signal, actions that end in contact), and the group-membership verb that was missing under the visual problem (D-people-circles)
- `docs/PHOTOS_PLAN.md` — household photos: the Photo primitive, albums, sharing, and the S3-compatible storage seam (D-photos-primitive, D-storage-seam)
- `docs/EMAIL_PLAN.md` — email import & monitoring: the mirror layer (D-mirror-layer) in its own database (D-mirror-database), multi-account IMAP sync, triage + sender-rule feedback loop, digest/urgent alerts, the boomerang family (D-email-monitoring), the hostile-input threat model
- `docs/RECIPES_PLAN.md` — the recipe box: the Recipe primitive and its ingredient parser, recipe books, sharing to the household and to people outside it by link, and the pantry/AI waves (D-recipe-primitive, D-share-link, D-pantry)
- `docs/EDUCATION_PLAN.md` — the Education hub as a personal school: the curriculum spine (per-learner Subject/Topic trees — D-education-spine), the open curriculum commons seeded from public standards (D-curriculum-commons), evidence-gated mastery states (D-mastery-evidence), FSRS spaced-repetition review (D-review-scheduler), interest-framed teaching and cross-lens subject suggestions, and the homeschool paperwork generators (D-learning-record)
- `docs/TASKS_PAGE_PLAN.md` — the Tasks page restructure: one section, two surfaces (the board leads, goals compress to a needs-attention strip with a Goals tab for planning), the capture box that routes day-sized input to a plain Task, finite-vs-ongoing progress framing, the paused state and staleness markers that defuse the goal graveyard, and the swipeable mobile board (D-tasks-two-surfaces, D-goal-shape, D-goal-capture-routing, D-goal-pause)
- `docs/CHAT_PLAN.md` — the chat surface, brought up to native-messaging quality on a phone: the screen/panel split, optimistic send, streaming replies (D-chat-shell, D-chat-optimistic, D-chat-stream)
- `docs/TRAVEL.md` — the Travel section: why it's a lens and not a page, the self-drawn world map of geotagged photos (no tiles, no geocoder, owner-only per Q14), and what the hub grows next (D-travel-facet)
- `docs/TRIPS_PLAN.md` — trips as a travel management tool: planned-ahead trips, stays and transport legs with booked/planned tracking, the where-you'll-be outlook and calendar band, and membership sharing that keeps everything coordinate-derived owner-only (D-trip-spine, D-trip-companions)
- `docs/READER.md` — the feed reader: Google Reader's shape over feeds the user chose, chronological on purpose (why the ranking and votes were built and then cut), the politeness rules for the one part of the app that polls strangers' servers, and the hostile-input handling for stranger XML (D-feed-reader)
- `docs/HOBBIES_HUB_PLAN.md` — folding the reader into the Hobbies hub: one river per hobby, why the model classifies each *feed* (one call per subscription) and never a story, and why everything it can't place lands in one real lens called Other Interests (D-hobby-feeds), and why the hobbies it suggests are clusters spotted in what you actually read (D-hobby-spotting)
- `docs/STORY_ROUTING_PLAN.md` — the broad feed problem: how the birding stories inside a general news feed reach the Birding hub — the model reads them, batched, but only from feeds it called *broad*, with the one amendment to "an item's tags are its feed's tags" (D-story-matching). §10 is the record of the term-matching version that was built here first and replaced (D-no-keyword-logic)
- `docs/EVENT_RADAR_PLAN.md` — events near you that you'd actually go to: places as the unit of subscription (gazetteer-named, radius + lead time, a trip's stay as a dated place — D-place-subscriptions), listing sources attached to a place (iCalendar feeds, schema.org `Event` and volunteer `JobPosting` pages, opt-in keyed providers; polled politely, never geocoded; a dated event or an undated volunteer *opening* — D-listing-feeds), the model reading each new happening once against the hobby lenses plus two owned sentences (interests, causes), with a watcher that proposes the ones inside a place's lead time and retires them on the date (D-event-radar), and a linked Meetup/Eventbrite account whose RSVPs are calendar sync, whose saves are pre-judged nudges, and whose groups are offered sources (D-radar-accounts). The Q9-free answer to "find meetups nearby". **Adding a listing kind?** Add it to `ListingSource::KINDS` (and `FETCHED_KINDS` if it is polled), a `Listings::Parse::<Kind>` and a branch in `Listings::Refresh#parse`; a keyed search is one entry in `ListingSource::PROVIDERS` plus `Listings::Providers::<Name>`, and it ships off by default behind its consent sentence
- `docs/PASSWORDS_PLAN.md` — the password vault: per-user envelope encryption, sharing, TOTP, import/export, and the agent-access bridge (D-passwords-vault, D-vault-crypto)
- `docs/DIARY_PLAN.md` — the diary: a second sealed container behind the keyring — everything encrypted but the date, the per-user diary-key tier, the recovery gate, emergency-access exclusion, and the extraction of the vault machinery into `VaultSealed` (D-diary-vault, D-vault-sealed). **Adding a third sealed container?** Include `VaultSealed`, add it to `VaultSealed::CONTAINERS` and to `VaultSession::COOKIES` (a name *and* a path — never widen an existing one), and nothing else.
- `docs/PETS_PLAN.md` — pets, blended into the existing hubs rather than given one of their own (built): why a pet is a *whom* and not a section, the `Pet` record plus a section lens per pet that makes "about Rex" an ordinary tag (D-pet-primitive), the care radar generalized from user to subject (D-pet-care-radar), and the food shelf that computes a reorder date and a budget line (D-pet-food-shelf). **Adding another record that owns a lens?** Add it to `Section::LENS_OWNERS`, add `Sections::Panels::<Model>Lens`, and create the lens with `Sections::Lens.create!` (never `find_or_create!` — an owned lens is never shared)
- `docs/PET_VACCINES_PLAN.md` — pet vaccination records (planned): one row per dose, titer or exemption with its own good-until date, the per-species vaccine catalog that claims only what the professional bodies publish and never a duration or a law, the Vaccinations card and visit-shaped log form, the reminder watcher that collapses one visit's vaccines into one nudge, the certificate intake kind, and the one-sheet share link for the kennel (D-pet-vaccinations)
- `docs/INTAKE_PLAN.md` — document intake (built): upload anything — a photo of a vet report, a scanned lease — and the app reads it (images through the vision rung photos already use), proposes the rows it implies against **one landing registry** whose kind classes declare the fields the model is told, the validation into the closed set, the write, and the preview all at once (D-landing-registry), and shows them on a review page where nothing lands without the click and the file is always kept (D-document-intake). **Adding a primitive?** Write its `Landing::<Kind>` or add it to `Landing::NOT_INTAKE` with a reason — the registry test fails until you do one or the other
- `docs/ABOUT_PLAN.md` — the `/about` pages: how the app explains itself to the person deciding whether to run it and the person already running it, the ten hubs, the tool pages generated from the registry, and the household switch that turns the whole public surface off (D-about-pages). **Adding a page?** One file per page under `app/views/about/{topics,sections,features,tools}/`, plus a row in the matching `About::Page` list — and a top-level page is registered in the same commit that writes its prose, since it has no generated content to fall back on
- `docs/REMINDERS_PLAN.md` — standing reminders: why recurrence lives on the Reminder and not on Event or Task, `deliver_at` as the next occurrence advanced by the same conditional update that claims the row, missed occurrences skipped rather than delivered late, the `RRULE` grammar extracted from the ICS importer into `Recurrence::Rule`, and plain-words capture that fills the form through the model and saves nothing (D-standing-reminders; Q-routines holds the chore-on-the-board question it declined)
- `docs/ARCHITECTURE.md` — schema, visibility model, adapter design, build sequence
- `docs/DESIGN.md` — design language: tokens, atoms, components, conventions

## Where we left off

Run `bin/status` — the build log, oldest first (`bin/status tail 10` for the
recent stretch). `docs/STATUS.md` carries what's next.

The log lives outside this file, and outside any single file, on purpose: it
grows on nearly every branch, so while it lived in CLAUDE.md it made this the
most conflict-prone file in the repo, and while it was one append-only
document every parallel branch collided on that. It is now one file per entry
under `docs/status/`. Add yours with `bin/status new "What landed"` — never by
editing an entry someone else's branch is holding.

## Parallel branches: conflict hygiene

Several branches land concurrently, so two rules for the global sequences:

- **New decisions get slug IDs, not sequence numbers.** Two in-flight branches
  can't see each other's claims, so a shared counter guarantees collisions (the
  D30 photos/task-chat clash cost a ~20-file renumber). New entries are
  `**D-kebab-slug.**` (e.g. `**D-photos-primitive.**`) — self-describing,
  greppable via the `D-` prefix, collision-proof. D1–D37 and Q1–Q19 keep their
  numbers; never renumber them. A slug is also the entry's filename, so the one
  case that still needs eyes — two branches picking the same slug for different
  decisions — surfaces as an add/add conflict on that path.
- **The decision log is one file per entry, so it can't conflict.** Add yours
  with `bin/decisions new D-kebab-slug "One-line statement"` — never by editing
  an entry another branch is holding. Entries live in `docs/decisions/<ID>.md`;
  `docs/DECISIONS.md` is now the front door that explains the layout, and
  `bin/decisions` reads the log. Each entry's first line is its group
  (`<!-- decided -->` / `<!-- resolved -->` / `<!-- open -->`), so promoting an
  open question to a decision is a one-word edit rather than a cut from one
  section and a paste into another. This replaced a single document where every
  branch inserted at the same anchor — the end of `## Decided` — and conflicted
  on a trivial keep-both every time.
- **Migration timestamps are claimed at generation time**: always create
  migrations with `bin/rails g migration` so they carry real second-resolution
  timestamps — never hand-rounded ones like `…180000`.
- **Registry hub files conflict by design; that's fine.** Lists everyone
  appends to (`ICON_PATHS`, `routes.rb`, `User` has_many, `Tool::SLUGS`,
  fixture files) merge with a trivial keep-both — resolve, don't redesign.
  (`docs/DESIGN.md` stays on the default strategy on purpose: unlike the two
  logs it is *edited* rather than appended to, so a conflict in a design rule
  is exactly the kind that deserves eyes — its atom registry is one role per
  line so that additions still merge keep-both.)
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
- **The build log is one file per entry, so it can't conflict.** Add yours
  with `bin/status new "What landed"` — never by editing an entry another
  branch is holding. This replaced a single append-only `docs/STATUS.md`
  carrying `merge=union`: union merge did resolve those appends silently in
  git, but GitHub computes a PR's mergeability *without* the repo's
  `.gitattributes`, so every branch that touched the log still showed a
  conflict on its PR page and needed a local merge to clear it. That is the
  general lesson for any file everyone appends to: a merge strategy only
  quiets your own git, while separate files quiet everything.
  Dropping the attribute has its own trap, which cost one silent bad merge
  the day the split landed: git resolves a merge using the **merging
  branch's** `.gitattributes`, not the incoming one, so a branch cut before
  the attribute was removed still unions — restoring the deleted entry list
  into `docs/STATUS.md` and reverting the split with no conflict, no
  markers, and nothing for a reviewer to notice. Whenever a merge strategy
  changes, read the affected file's diff before committing the merge that
  brings the change in.
