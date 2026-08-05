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
Current plan: after Milestone 1, pressure-test with the **"eviction notice" Situation** rather than a section alone — it exercises Rights *and* the cross-section spawning mechanics (D7) in one pass. — *Planned, not started.*
