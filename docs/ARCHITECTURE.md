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
| `Task` | title, notes, due_on (opt), completed_at, goal FK (opt) | Today/Inbox feed |
| `Document` | title, description, extracted_text, summary + Active Storage `file` | extracted_text/summary filled by the AI pipeline later |
| `Person` | name, relationship, email, phone, birthday, notes, linked_user FK (opt) | Contacts + context |
| `Goal` | title, description, status (backlog/active/done), target_on | Kanban; has_many tasks/events (nullify). Situations (D7) = a Goal + spawned multi-tagged Tasks/Events |
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

## Model integration (D10 — built in a later step of Milestone 1)

- `ModelProfile` (table arrives with the feature): name, base_url, api_key, model. Multiple profiles allowed; tasks route to a profile (cheap model for tagging, big model for drafting).
- One adapter class speaking OpenAI-compatible chat completions. No vendor gems; ~200 lines we own and audit. Remote first; Ollama/llama.cpp later by changing base_url.
- First and only Milestone-1 AI feature: document upload → Solid Queue job → text extraction → summary + suggested section tags written back to the Document, surfaced as *suggestions* (trust ladder, D6).

## Build sequence

1. ✅ Schema + models + tests (this change)
2. Auth flows wired to households (invite/create household members), `Current.user` conventions
3. Primitive CRUD (Hotwire), cross-cutting views: Calendar, Today, Vault, Boards, Dashboard shell
4. Settings: section toggles, sharing grants UI
5. Document AI pipeline + `ModelProfile` + adapter
6. Situation pressure-test: "eviction notice" (Q7)

Deferred deliberately: encryption at rest & deployment hardening (post-foundation, per D10), community packs (D11), voice, FTUE, agent mode.
