# DECISIONS.md

Decision log from design sessions. Format: decision, reasoning, status.

## Decided

**D1. Model-agnostic; no model development or specific integrations.**
Open configuration lets users choose any local (or remote) model. Models are swappable commodities; we build the layer around them. — *Locked.*

**D2. Local-first, self-hostable, open source.**
Follows directly from mission (no chokepoint, no rented dependency, privacy for the most sensitive sections). — *Locked.*

**D3. Top-level sections:** Health, Hobbies, Education, Career, People, Money, Rights.
- "Friends" renamed → **People** to include family, communities, church, clubs, meetups (heavier caregiving/family use cases need an inviting home).
- Money subsections: Budget, Debt, Taxes, Assets, Bills, Subscriptions, Benefits.
- Rights subsections: Immigration, Renting, Voting, Disputes.
- "Disputes" chosen over "Advocacy" (nonprofit-speak) and "Appeals" (sounds like you already lost) — most self-explanatory to a stressed user. — *Locked.*

**D4. Sections are toggleable per-user; FTUE picks defaults.** — *Locked.*

**D5. Lens-over-primitives data model.**
One shared pool of primitives (Events, Tasks, Documents, People, Goals/Projects, Notes/Memory), multi-tagged by section. Sections never own separate databases. Cross-cutting views (Calendar, Today, Documents vault, Goals boards, Dashboard) fall out for free. — *Locked; the key architectural decision.*

**D6. Three modes: Organize (passive) → Tools (self-serve) → Agent (proactive).**
Also the build order and trust ladder. Agent behavior is per-section user-controlled (agent aggressiveness dials live in the same settings surface as section toggles). — *Locked.*

**D7. Situations as a first-class concept.**
Life events spanning sections ("lost my job," "eviction notice") modeled as Goals spawning multi-tagged Tasks/Events. — *Locked conceptually; design TBD.*

**D8. Household multi-tenancy.**
One self-hosted instance serves a household; each member is an independent user with their own data. Cross-user coordination (e.g., the AI booking a couple's appointments back-to-back so they can carpool) is a target capability. Household members as *contacts* (Person records) are modeled separately from household members as *users* (logins), with an optional link between them. — *Locked.*

**D9. Private by default; sharing is explicit, visible configuration.**
Every item belongs to its creator and is invisible to other household members until shared. Sharing works per-item and per-section ("share all my Money items with my spouse"). Cross-user AI features operate only over what's shared with the requesting user. We make **no moral/ethical judgments** in the product (e.g., whether parents may access children's data) — access control is user-visible configuration, never hidden defaults. People control their configuration, not us. — *Locked.*

**D10. Remote models first; local models are a config swap.**
Build against a single OpenAI-compatible chat-completions adapter (configurable base URL, key, model name). That wire format is spoken by OpenAI, OpenRouter, Groq, Anthropic's compatibility endpoint — and by Ollama/llama.cpp/LM Studio, so swapping in local models later is configuration, not code. Security/encryption hardening is deliberately deferred until after the foundation is built. — *Locked.*

**D11. Workflow packs are first-party only, for now.**
We author packs ourselves; users inherently trust first-party content. Community authoring/distribution (and the sandboxing questions it raises) is deferred. — *Locked for now.*

**D12. Sections are a database taxonomy table, not code enums.**
Single `sections` table with optional `parent_id` for subsections. Toggles, tagging, and any future re-parenting (e.g., moving Benefits) become data changes. — *Locked.*

**D13. Milestone 1 = Organize core, AI-lite.**
Full schema (households/users, sections taxonomy, six primitives, tagging, sharing grants), CRUD, cross-cutting views, section toggles. AI appears in exactly one place: document upload → summary + suggested tags. Independently useful per the "value without AI" principle. — *Locked.*

**D14. Technical stack.**
Rails 8.1, Ruby 3.3+, SQLite (the user's life is literally one file they own), Solid Queue/Cache/Cable (zero external services), Hotwire, Propshaft, Kamal + Dockerfile for the one-command-install path. Rails 8 built-in authentication. — *Locked.*

**D15. Onboarding: first-run setup + link-based invitations.**
A fresh instance redirects every visit to `/setup`, which creates the household and its first (admin) user in one form — solo users are fully onboarded there and never see invite concepts. Admins invite others by generating **signed join links** from Settings (name only; copied and sent over whatever channel the household already uses). No email delivery dependency — self-hosted instances rarely have SMTP. Tokens are single-use, expire in 7 days, die on revoke. No public signup, no account merging. Admins can promote/demote others and remove members; acting on yourself is forbidden, which structurally guarantees ≥1 admin. — *Locked.*

**D16. Capture is minimal; AI files the rest.**
The new-item forms were walls of fields (dates, goal, ~20 section checkboxes) that made the user do the machine's job. Capture is now the bare minimum per primitive — task: a title (quick-add bar on the index + minimal `/tasks/new`); event: a title and a day; note: just the body; goal: a title; person: a name plus an optional one-liner; document: just the file (title falls back to a cleaned-up file name) — and a best-effort, silent-on-failure `Categorize*Job` auto-applies section tags plus what the text implies: a task's due date ("renew passport by Friday"), an event's time of day ("dentist at 3pm" flips all-day to timed), a goal's target date, a person's relationship label, a note's title. Document analysis auto-applies its section suggestions too, but only to untagged documents — once the user has tagged one, suggestions stay suggest-and-click (D6). Anything the user set by hand — tags, dates, times, titles, relationships — is never overwritten; a mis-filed item is low-stakes and fixable in the edit form, which keeps all fields for refinement.
Date UX: date fields use the native picker (typeable) plus one-click shortcut chips (Yesterday/Today/Tomorrow/Next week/Next month) rendered server-side. Events store `starts_at`/`ends_at` datetimes but forms speak in virtual parts — a day plus optional start/end times; a blank start time *is* the all-day flag, so the checkbox is gone. Nobody types a datetime anywhere in the app. — *Locked.*

**D17. Tasks and Goals are one section; goals are AI-planned.**
Goals and Tasks merged into a single **Tasks** section (the separate Goals boards page is gone; `/goals` redirects). The two stay distinct models with distinct meanings: a Goal is a high-level outcome ("get a job"); a Task is day-sized with a clear done/not-done state. The section leads with one input — "What do you want to accomplish?" — which always creates a Goal, and `BreakDownGoalJob` (one LLM call, replacing `CategorizeGoalJob`) breaks it into 3–10 scheduled, section-tagged tasks *and* files the goal itself. Steps auto-apply (D16 discipline: silent on failure, hand-set fields never overwritten, pruning is one click); the goal page has "suggest more steps," which shows the model the existing plan and appends only what's missing. The **kanban moved from goals to tasks** with daily-workload columns **Later / Today / Done**: Today = pulled-in-by-hand ∪ due-today/overdue (so breakdown-scheduled tasks surface themselves each morning with no cron), Done is derived from `completed_at`, and "not today" bumps a due task to tomorrow so it resurfaces. Goals lost their board and their `backlog` status (now active/done, auto-finishing when the last step completes, reactivating when one reopens) and render as a progress strip above the board; task cards/rows show a flag chip for their goal. This is the mechanism Situations (D7) will ride on — a Situation is a Goal with a richer breakdown prompt. — *Locked.*

**D18. Section pages are three zones: Act / Attend / Browse.**
Every section page composes all three modes: **Act** (tool cards registered for the section — present even when the section is empty, replacing the dead-end empty state), **Attend** (pending agent suggestions tagged with the section — the pull-side slice of the Dashboard's push feed), **Browse** (the existing filtered primitive lists + section-pre-tagged quick capture). Subsection pages get the identical anatomy; subsection-registered tools also appear on the parent. Full design in `ROADMAP.md` §1. — *Provisional until the M2.1 build pass.*

**D19. A Tool is a first-party pipeline: owned context → LLM call(s) → draft primitives, suggest-and-apply.**
Two kinds: **plan tools** (Goal + multi-tagged Tasks/Events via the D17 breakdown pipeline with a tool-specific prompt — Situations (D7) are exactly this) and **draft tools** (reviewable artifact as a draft Note/Document + optional follow-ups). Tools are code (`app/tools/`, `Tool::Base` + registry — behavior is code even though taxonomy is data per D12); runs are rows (`tool_runs`: inputs, status, output, created primitives; live-updating run page). Output is always draft output — the app never sends anything externally in M2. All M2 tools are **Tier A** (reason over owned data only; no assumed web capability — the model-agnostic constraint). Full design + first tool slate in `ROADMAP.md` §2. — *Provisional until the M2.1 build pass.*

**D20. The agent proposes; the user disposes.**
The agent's only write surface is a new `suggestions` table (Sectionable; rationale, action payload, fingerprint deduping, pending/accepted/dismissed/snoozed). Signals come from deterministic **watchers** (`app/watchers/`, SQL-first, LLM only for phrasing/ranking/digest). Per-section dials on `user_sections`: **Off / Quiet (default: weekly, in-app only) / Active (daily, + Today)**. Cross-user suggestions read strictly through `visible_to` (D9). Notification channels deferred (Q10). Full design in `ROADMAP.md` §3. — *Built through M3.2 (suggestions table, four watchers, Off/Quiet/Active dials in Settings honored by weekly/daily scans) plus M3.3's phrased weekly digest (LLM phrases, never decides; silent failure). Remaining: cross-user coordination suggestions (needs its own design) and notification channels (Q10).*

**D21. Outside accounts link per-user with scope dials that default to everything.**
`linked_accounts` (one row per user per provider) is the layer that connects the services a user already lives in — email (IMAP), address book (CardDAV), calendar (CalDAV), Facebook, LinkedIn — so the assistant can eventually draw on them. Providers are first-party registry entries in `LinkedAccount::PROVIDERS` (D11: adding a service = one entry declaring label, credential fields, scopes). Access is scope-gated per link and **defaults to full access**: linking is consent, and we store only the scopes the user switched *off* (`disabled_scopes`), so a scope added to a provider later is granted to existing links without backfill — the same enabled-unless-disabled convention as section toggles (D4). The dials are visible, user-controlled configuration on the Settings page (D9: no hidden defaults), and consumers must read through `allows?`, which fails closed on unknown scopes. Credentials are a plaintext JSON blob for now — the same deliberate encryption deferral as `model_profiles.api_key` (D10/D14), and the same D14 leftover will cover both. Per-provider sync jobs/importers/tools come per demand, each honoring the link's scopes. The first two consumers are built on a shared `Dav::Client` (plain Net::HTTP, RFC 6352/4791 discovery with `/.well-known` fallback, or a pasted collection URL directly): `People::CarddavSync` pulls vCards through `People::Import`, and `Events::CaldavSync` pulls iCalendar payloads through `Events::Import` (its REPORT carries a time-range filter matching the Ics importer's 1-month-back/12-ahead window, so servers don't ship decades of history) — the same normalize/dedupe paths as file uploads, so sync and upload can never disagree. Both run read-only, gated on the link's "read" scope via `allows?` inside the service (not just the UI); providers with a consumer name it in the registry (`sync_service:`), and one `SyncLinkedAccountJob` dispatches through that, firing on link and from a "Sync now" button, recording `synced_at`/`sync_error` on the link for the Settings card. — *Built (linking UI, scope dials, registry, contacts + calendar sync). Remaining: the email consumer, recurring background sync, and OAuth (see D22).*

**D22. OAuth for linked accounts: bring-your-own app, never a central broker.**
When a provider requires OAuth (Google's CardDAV/CalDAV endpoints are the motivating case — password auth is shut off there), the household registers its **own** OAuth app (a Google Cloud project's client_id/client_secret) and pastes those into the instance, which then runs the standard authorization-code flow against its own URL. This is the Home Assistant/Nextcloud pattern, and it follows from the mission: a project-run OAuth broker would be a central chokepoint — a landlord we'd become — plus a metadata leak and a verification/hosting liability. The friction (a ~10-minute, well-documented, one-time setup per household, and the provider's "unverified app" interstitial) is the honest price of ownerless infrastructure, and it's paid by the admin once, not by every member.
Design sketch when we build it: (1) registry entries grow an `auth:` kind — `:fields` (today's forms) or `:oauth` with authorization/token endpoints and a **scope map from our D21 scope keys to provider OAuth scopes**, so the visible dials become the actual consent requested — unchecking "Read your calendars" before connecting means the token literally can't read calendars, which is stronger than local gating; (2) a household-level `oauth_apps` table (client_id/secret per provider, admin-managed like `ModelProfile`) while tokens stay per-user on `linked_accounts.credentials` (access/refresh token + expiry); (3) authorize + callback routes with `state` CSRF and a small `Oauth::Client` (plain Net::HTTP, mirroring `Llm::Client`/`Dav::Client`) handling code exchange and refresh; (4) a first-class **Google** provider exposing gmail/calendar/contacts scopes under one link, whose sync consumers reuse the existing importers.
Scope honesty: OAuth does **not** unlock Facebook friends or LinkedIn connections — those APIs are closed to non-partners regardless of auth. Their route stays official data-export files through the file importers; their registry entries should eventually say so rather than promise sync. Sequencing: build alongside-or-after the email consumer, whenever the first OAuth-only consumer (Google sync) is next up — not before, since DAV + app passwords already cover iCloud/Fastmail/Nextcloud today. — *Direction locked (BYO app); build not started.*

## Resolved questions

**Q1. Benefits placement: Money.**
Discovery argument wins: people looking for money help should find unclaimed benefits; Rights stays focused on adversarial/legal. With D12 this is a data change if it ever moves. — *Resolved.*

**Q2. Work rights live in both Career and Rights via multi-tagging.**
The lens model answers its own question — if an item fits two sections, tag it with both (D5 working as designed). — *Resolved.*

**Q6. Technical stack.** — *Resolved; see D14.*

## Open questions

**Q3. Insurance navigation split.**
Decided in principle: care and coverage navigation in Health; medical billing disputes in Rights → Disputes. Watch for UX confusion. — *Provisional.*

**Q4. Project name.** — *Not started; repo is "assistant" as a working title.*

**Q5. FTUE flow design.** — *Not started.*

**Q7. First deep-dive to pressure-test the model.**
Current plan: after Milestone 1, pressure-test with the **"eviction notice" Situation** rather than a section alone — it exercises Rights *and* the cross-section spawning mechanics (D7) in one pass. Now scheduled as build step **M2.2**: the eviction Situation is the first *plan tool* (D19), so the pressure test rides the tools infrastructure instead of preceding it.
Reprioritized 2026-08: the plan-tool *mechanism* was proved by "Learn something" (M2.2 as built) instead, and the cross-section pressure test now rides the first Situation shipped — **"moving"**, the widest-audience candidate (M2.4). Eviction itself is deferred until users ask: low-frequency, narrow audience, and nothing about it is architecturally special anymore — it's one more plan tool with a rich brief. — *Mechanism proven; cross-section test planned (M2.4).*

**Q8. Contact-recency signal for the stay-in-touch watcher.**
Resolved (M3.2): `people.last_contacted_on`, set by a one-tap **"Log contact today"** button on the person page — deliberately manual, because the app can't see your texts and shouldn't pretend to. The watcher only ever speaks about people the user has logged contact with (no signal, no nudge), fingerprinted per person per quarter; accepting opens the Reconnect tool prefilled. Inference from Events/Notes was considered and dropped — guessed recency produces wrong nudges, and wrong "call your mom" nudges cost trust. — *Resolved.*

**Q9. Tier-B tool capabilities (live external data).**
Tools that need the live web (real provider directories, current benefit rules) are deferred; M2 tools are Tier A only (owned data). Revisit whether a `capabilities` flag on `ModelProfile` is worth building once provider browsing support stabilizes, or keep leaning on user-supplied documents. — *Not started.*

**Q10. Agent notification channels.**
Self-hosted instances rarely have SMTP (the D15 argument), so the agent is in-app-only (Dashboard/section/Today) through M3. Email/push/webhook channels need their own design. — *Not started.*
