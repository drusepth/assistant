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
The agent's only write surface is a new `suggestions` table (Sectionable; rationale, action payload, fingerprint deduping, pending/accepted/dismissed/snoozed). Signals come from deterministic **watchers** (`app/watchers/`, SQL-first, LLM only for phrasing/ranking/digest). Per-section dials on `user_sections`: **Off / Quiet (default: weekly, in-app only) / Active (daily, + Today)**. Cross-user suggestions read strictly through `visible_to` (D9). Notification channels deferred (Q10). Full design in `ROADMAP.md` §3. — *Provisional until the M3.1 build pass.*

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
"It's been a while since you talked to Mom" needs a signal we don't store: likely `people.last_contacted_on` (one-tap "log contact" + updated on suggestion accept) combined with inference from Events/Notes involving the person. Design before building the watcher (M3.2). — *Not started.*

**Q9. Tier-B tool capabilities (live external data).**
Tools that need the live web (real provider directories, current benefit rules) are deferred; M2 tools are Tier A only (owned data). Revisit whether a `capabilities` flag on `ModelProfile` is worth building once provider browsing support stabilizes, or keep leaning on user-supplied documents. — *Not started.*

**Q10. Agent notification channels.**
Self-hosted instances rarely have SMTP (the D15 argument), so the agent is in-app-only (Dashboard/section/Today) through M3. Email/push/webhook channels need their own design. — *Not started.*
