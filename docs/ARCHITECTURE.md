# ARCHITECTURE.md

Technical architecture for Milestone 1 (Organize core, AI-lite). Decisions referenced as D-numbers from `DECISIONS.md`.

## Stack (D14)

| Layer | Choice | Why it serves the mission |
|---|---|---|
| Framework | Rails 8.1, Ruby 3.3 | One person can build and maintain the whole thing |
| Database | SQLite | The user's entire life is *literally one file they own*; backup = copy a file |
| Jobs/Cache/Cable | Solid Queue / Solid Cache / Solid Cable | Zero external services — nothing to install beyond the app |
| Frontend | Hotwire (Turbo + Stimulus), Propshaft, importmaps | No node toolchain; server-rendered simplicity |
| Files | Active Storage, local disk | Documents stay on the user's machine |
| Auth | Rails 8 built-in authentication generator | No auth SaaS dependency |
| Deploy | Dockerfile + Kamal | The one-command-install path |
| Tests | Minitest + fixtures | Rails default; low ceremony |

Everything the app needs runs in one container with one mounted volume (`storage/` holds the SQLite databases *and* Active Storage files). That volume **is** the user's exportable life archive.

## Domain model

### Tenancy & identity (D8)

```
Household 1──* User 1──* Session
```

- `households` — name.
- `users` — household FK, name, email_address (unique), password_digest, admin flag. Admins manage the household (create accounts, configure instance).
- A household member as a *contact* is a `Person` record; as a *login* it's a `User`. `people.linked_user_id` optionally connects the two (D8) — this is what lets cross-user AI features ("book us back-to-back appointments") resolve "my wife" to a real account whose shared data it may read.

### Sections taxonomy (D3, D12)

- `sections` — slug (unique), name, self-referential `parent_id`, position. Seeded with the 7 top-level sections; Money and Rights carry subsections. Re-parenting (e.g., Benefits Money→Rights) is a data migration, not a refactor.
- `user_sections` — per-user section toggles (D4). Rows are created lazily; absence = enabled default (FTUE will later write explicit rows).

### Primitives (D5)

Six tables, deliberately boring. Every primitive `belongs_to :user` (its owner) and includes two concerns:

| Model | Own columns | Notes |
|---|---|---|
| `Event` | title, description, starts_at, ends_at, all_day, location, goal FK (opt) | Calendar feed |
| `Task` | title, notes, due_on (opt), completed_at, bucket (later/today), goal FK (opt) | Today/Inbox feed; Later/Today/Done board (D17 — Done derived from completed_at, Today = bucket ∪ due) |
| `Document` | title, description, extracted_text, summary + Active Storage `file` | extracted_text/summary filled by the AI pipeline later |
| `Person` | name, relationship, email, phone, birthday, notes, linked_user FK (opt) | Contacts + context |
| `Goal` | title, description, status (active/done), target_on, broken_down_at | Lives inside the Tasks section (D17); `BreakDownGoalJob` plans it into scheduled tasks; auto-done when the last step completes; has_many tasks/events (nullify). Situations (D7) = a Goal + spawned multi-tagged Tasks/Events |
| `Note` | title (opt), body | The memory layer's inspectable form |

**`Sectionable`** — `section_taggings` (polymorphic join to `sections`, unique per item+section) gives multi-tagging and the `in_section(section)` scope. Cross-cutting views are just unscoped queries; section pages are `in_section` queries. No section ever owns a table.

**`Visible`** — ownership + the sharing model, below.

### Sharing: private by default, explicit grants (D9)

One table expresses both sharing granularities:

- `access_grants` — grantor (User), grantee (User), polymorphic subject, unique per (grantor, grantee, subject).
  - **Item grant**: subject is a specific primitive → grantee sees that item.
  - **Section grant**: subject is a `Section` → grantee sees *all of the grantor's items tagged with that section* ("share all my Money items with my spouse"), including items tagged later.

Validations enforce: grantor ≠ grantee, same household, and (for item grants) grantor owns the subject.

`Visible` provides the single authorization query, `Model.visible_to(viewer)`:

```
owned by viewer
OR an item grant to viewer exists for this row
OR a Section grant to viewer exists from this row's owner
   for a section this row is tagged with
```

implemented as correlated `EXISTS` subqueries so it stays one SQL query and composes with any other scope (`Event.visible_to(me).in_section(money)`). `visible_to?(viewer)` delegates to the same scope — one source of truth. Controllers will use `visible_to(Current.user)` everywhere; there is no other read path. Cross-user AI features get their entire view of another user through this same scope — the AI can never see more than the humans chose to share.

No moral/ethical stances are encoded (D9): defaults are private, every grant is a visible row a user created, and the settings UI will render grants explicitly. Parent/child access is whatever grants the household configures.

## Model integration (D10 — built)

- `ModelProfile`: one per household for now, managed by admins from Settings via a **provider picker** (`ModelProfile::PROVIDERS`): **OpenAI** (key + model name), **Anthropic** (Claude API key + model name, over Anthropic's OpenAI-compatibility endpoint), **Google** (Gemini API key + model name, over Gemini's OpenAI-compatibility endpoint), **Chroma Golem** (key only — router-style, model chosen on their site; we send an opaque `client_id` per their API convention), and **Custom endpoint** (raw base_url + model, for Ollama/OpenRouter/Groq/llama.cpp). All presets ride the same adapter; a preset may also carry `json_mode:` and `max_tokens:` for the quirks its endpoint has (D-provider-presets), and `cloud: true` if it is somebody else's computer. `allow_cloud_models` (default true) gates that cloud set: unticked, the picker offers only what the household runs itself, a validation refuses the pair, and `#client` raises (D-local-first-models). api_key encrypted at rest per D14. Multiple profiles / per-task routing later.
- `Llm::Client` (`app/services/llm/`): the one adapter — OpenAI-compatible chat completions over Net::HTTP, JSON response mode, friendly `Llm::Error`s. No vendor gem. JSON is requested with `response_format` by default, or in the prompt for endpoints that ignore that field (`json_mode: :prompt`).
- Document understanding: upload (or Analyze button) → `AnalyzeDocumentJob` → `Documents::Analyze` extracts text (PDF via pdf-reader; text/markdown/CSV; other types fail with a friendly message) → one chat call returns `{summary, sections}` against the seeded taxonomy → stored on the Document with status queued/processing/analyzed/failed.
- Trust ladder (D6): section suggestions are chips with per-chip Apply buttons on the document page — the AI never tags anything itself.

## Design system

Tailwind CSS v4 (standalone binary — no Node) + ViewComponent + a default
`ApplicationFormBuilder`. Tokens, atoms, components, and conventions are
documented in `DESIGN.md`; the rule is that views never hand-roll visual
patterns — everything reusable lives in one redesignable place.

## Build sequence

1. ✅ Schema + models + tests
2. ✅ Design system (Tailwind v4 tokens + atoms, ViewComponents, form builder)
3. ✅ Primitive CRUD, cross-cutting views (Dashboard, Today, Calendar, Vault,
   Boards, section pages), Settings (section toggles), sharing UI (item +
   section grants)
4. ✅ Household member management (D15): first-run `/setup` creates
   household + admin; link-based invitations (`Invitation` +
   `generates_token_for`, single-use, 7-day expiry, revocable); admin
   role management and member removal from Settings
5. ✅ Document AI pipeline: `ModelProfile` + `Llm::Client` adapter +
   `AnalyzeDocumentJob` (summary + suggested tags, human-applied)
6. ✅ Tools foundation (M2.1 — D18/D19, see `ROADMAP.md`): section pages
   lead with an Act zone of tool cards; empty states offer tools + capture
   pre-tagged with the section; `Tool::Base` + explicit registry
   (`app/tools/`), `tool_runs`/`tool_run_items` + `ToolRunJob` + live run
   page; first tool: Draft a dispute letter (Rights → Disputes)
7. ✅ First plan tool (M2.2 — "Learn something"): `Goals::BreakDown#plan!`
   + optional `brief` shared by `BreakDownGoalJob` and plan tools; zero
   new schema (a plan tool is goal capture with framing). Q7's
   cross-section test now rides the first Situation ("moving", M2.4)
8. ✅ Suggestions core (M3.1 — D20, see `ROADMAP.md`): `suggestions`
   table (fingerprint-deduped, action payloads materialized on accept),
   deterministic watchers (`app/watchers/` + `Watcher::SLUGS` registry),
   `AgentScanJob` weekly fan-out (hardwired Quiet), Dashboard feed +
   section Attend zones; first watcher: checkup cadence
9. ✅ Coverage tools + first Situation (M2.3/M2.4): doctor-visit prep,
   cancel-subscription, reconnect (person input kind), "Plan a move" —
   all on shared `Tool::Base` contracts (DRAFT_FORMAT / plan_goal!)
10. ✅ Agent dials + watcher slate + digest (M3.2/M3.3):
    `user_sections.agent_level` (Off/Quiet/Active) in Settings, honored
    by weekly/daily scan cadences; stay-in-touch (manual
    `people.last_contacted_on`, Q8), renewal radar, goal stall;
    `Users::WeeklyDigest` phrases the Dashboard banner (LLM phrases,
    never decides; silent failure)
11. Remaining: cross-user coordination suggestions (design first),
    notification channels (Q10), D14 leftovers (export, api_key
    encryption), FTUE (Q5)

Deferred deliberately: encryption at rest & deployment hardening (post-foundation, per D10), community packs (D11), voice, FTUE, agent mode.
