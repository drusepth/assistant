# ROADMAP.md

Design for Milestones 2 (**Tools**) and 3 (**Agent**) — the second and third rungs of the D6 trust ladder — plus the **section page anatomy** that gives all three modes a home on one page. Milestone 1 (Organize) is complete; this doc is what "get started on it next" means.

Decisions proposed here are logged as **D18–D20** in `DECISIONS.md` (provisional until the first build pass proves them).

---

## 1. Section page anatomy (D18)

Today a section page is one thing: a tag-filtered list of primitives. That is Organize working as designed — and it also means an empty section is a dead end (an empty lens over zero items is zero content). The fix and the Tools/Agent homes are the same design:

Every section page is composed of **three zones**, top to bottom:

| Zone | Mode | Content |
|---|---|---|
| **Act** | Tools | "What I can do here" — a compact row of tool cards registered for this section. Always present, even (especially) when the section is empty. |
| **Attend** | Agent | Pending suggestions tagged with this section. Renders nothing until Milestone 3 ships and there are suggestions. |
| **Browse** | Organize | The existing filtered primitive lists, plus quick capture pre-tagged with the current section. |

Ordering rationale: Act is short and fixed-size (a card row), Attend is a handful of items at most, Browse is the long tail. The page leads with what the app can *do*, surfaces what *needs attention*, then lets you *go deep* — without burying the data that makes the section trustworthy in the first place.

**The empty state becomes the front door for Tools.** "Nothing in Career yet" + a lone Add-a-task button is replaced by: this section's tool cards, plus per-primitive quick capture (each pre-tagged with the section). A section with no data still answers "why would I come here?"

**Subsections** keep the existing header chips for navigation. A subsection page gets the identical anatomy; a tool registered on a subsection (e.g. `rights.disputes`) appears on both the subsection page and its parent's Act zone.

**Push/pull stays intact** (PRODUCT.md thesis: sections are pull, Dashboard/Calendar/Today are push). The Dashboard remains the *primary* surface for agent suggestions; a section's Attend zone is the pull-side slice of the same rows, not a second system.

---

## 2. Milestone 2 — Tools (D19)

### What a tool is

A **Tool** is a first-party, parameterized pipeline:

> **gather owned context → one or a few LLM calls → draft primitives, suggest-and-apply.**

Tools never produce free-floating chat output. Every result lands as primitives (or an artifact attached to the run), so tool output is owned, section-tagged, shareable via the normal grants, and visible in Calendar/Today/Dashboard like everything else. This is the concrete contract behind the "workflow packs" idea (D11): a pack is a bundle of tool definitions, and first-party-only means they are Ruby classes in this repo, not user-installed content.

### Two kinds of tool

- **Plan tools** create a Goal plus 3–10 scheduled, multi-tagged Tasks/Events — by riding the existing D17 pipeline: the tool creates a plain Goal and hands it to the same `Goals::BreakDown` that plans every goal, passing an optional **brief** (framing text injected into the one shared prompt) that shapes the steps. A plan tool adds **no schema and no pipeline of its own** — it is goal capture with framing. **Situations (D7) are exactly plan tools** with richer briefs spanning sections.
- **Draft tools** produce a reviewable text artifact — a dispute letter, a doctor-visit prep sheet — stored as a draft Note or Document linked to the run, optionally with follow-up Tasks/Events (e.g. "mail by Friday" when a letter has a deadline).

### Tool definitions (code, not DB)

Sections are data (D12) because they're taxonomy; tools are **code** because they're behavior. Each tool is a class in `app/tools/` inheriting `Tool::Base` with a declarative surface:

- `slug`, `title`, `description` — card copy for the Act zone.
- `sections` — section slugs it registers on (subsection slugs welcome).
- `kind` — `:plan` or `:draft`.
- `inputs` — the minimal form shown on invocation. D16 discipline applies: ask only what cannot be inferred or read from owned data (usually 0–2 fields — "which document?", one free-text line).
- `context` — which owned data the run reads, always through `visible_to(Current.user)` scopes (e.g. Health-tagged events/notes/documents). The AI never sees more than the invoking user can.
- `prompt` — the template that turns context + inputs into the LLM call(s).

A registry (`Tool.for_section(section)`) is how section pages discover their cards. No routes-per-tool: one `tool_runs` controller handles invocation generically.

### Runs

New table **`tool_runs`**: user, `tool_slug`, `inputs` (JSON), status (`queued/running/done/failed`), error, `output` (JSON), and an association to the primitives it created. The run's show page is the live-updating (Turbo Stream) progress + results surface, same UX pattern as document analysis, and doubles as history ("the letter I drafted in March").

### Trust ladder discipline

Tool output is **draft output**:

- Plan tools auto-apply the way D17 breakdown already does — silent on failure, pruning is one click, hand-set fields never overwritten.
- Draft tools produce an artifact for review. In Milestone 2 the app never *sends* anything on the user's behalf — no email, no submissions; the user copies/downloads the letter. Acting externally is agent-era territory and its own consent design.

### Capability honesty (the model-agnostic constraint)

We can't assume the configured model can browse the web. Tools split into two tiers:

- **Tier A — reasons over owned data only.** Works with any OpenAI-compatible endpoint, local models included. **All Milestone 2 tools are Tier A.**
- **Tier B — needs live external data** (real provider directories, current benefit rules). Deferred until either a `capabilities` flag on `ModelProfile` is worth building or the user supplies the data themselves.

The canonical "find in-network cardiologists" example gets a Tier-A reframing: **"prep me to find a doctor"** — read the insurance documents already in the vault, produce a call script, the in-network questions to ask, and a search checklist. Same user outcome, no capability lie. (Logged as open question Q9.)

### First tool slate

Ordered to prove the frame (one draft tool, one plan tool), then spread everyday coverage. Reprioritized 2026-08: disputes and evictions are **low-frequency, high-stakes** — right for the mission, wrong for making the app feel alive in week one — so the everyday tools and the broadest Situation moved up.

1. ✅ **Rights → Disputes: "Draft a dispute letter"** *(draft — built, M2.1)* — proves the draft contract; reads a chosen Document (bill, denial, collection notice) + one line of user intent → formal letter + follow-up Tasks.
2. ✅ **Education: "Learn something"** *(plan — built, M2.2)* — proves the plan contract end-to-end: topic → Goal + paced, filed, scheduled steps through the shared breakdown pipeline.
3. **Health: "Doctor-visit prep"** *(draft)* — reads Health-tagged items → question list + one-page history summary to bring to the appointment.
4. **Money → Subscriptions: "Cancel this subscription"** *(draft)* — cancellation letter/script + a reminder Task.
5. **People: "Reconnect"** *(draft)* — reads a Person + what's known about them → message draft + catch-up talking points. Deliberately seeds the Milestone 3 stay-in-touch watcher (its accept action runs this tool).
6. **Situations** *(plan tools with rich cross-section briefs)* — **"Moving" first**: the widest-audience Situation, and now the Q7 cross-section pressure test. "Eviction notice", "lost my job", "new baby", "new diagnosis" follow demand; eviction is deferred until users ask.

---

## 3. Milestone 3 — Agent (D20)

### Principle: the agent proposes; the user disposes

The agent's **only write surface is the `suggestions` table**. It never creates, edits, or completes user data on its own — accepting a suggestion is what materializes anything, and acceptance is always one explicit click. This is the same suggest-and-apply discipline as D6/D16, applied to the proactive mode.

### The Suggestion primitive

New table **`suggestions`**: user, title, body (the rationale — *why* the app is speaking up), kind (`nudge/heads_up/insight`), `watcher_slug` (source), status (`pending/accepted/dismissed/snoozed` + `snoozed_until`), an action payload (JSON describing what accept does — create this Event, create this Task, run this Tool with prefilled inputs), and a **fingerprint** (watcher + subject) so a dismissed nudge doesn't reappear next scan. Suggestions include `Sectionable`, which is what makes the Attend zone and Dashboard feed plain `in_section`/unscoped queries — the lens model working unchanged.

### Watchers: deterministic-first

Each watcher is a class in `app/watchers/` with a `slug`, `sections`, and `scan(user)` that emits candidate suggestions. **The signal comes from SQL, not model calls** — cheap, private, and it works identically with every model (including none). The LLM is optional garnish: phrasing, ranking, and the Dashboard's synthesized digest. Launch watchers:

- **Checkup cadence** (Health) — no Health-tagged event in the past N months and none upcoming → "you're due for a checkup," accept = create the Event, with free-day candidates read from the calendar.
- **Stay in touch** (People) — a person's contact recency exceeds their usual rhythm → "it's been a while since you talked to Mom," accept = run the Reconnect tool prefilled.
- **Renewal radar** (Money/Rights) — a renewal/lease-end/expiry Event approaching with no follow-up work attached → "your lease ends in 60 days."
- **Goal stall** (Tasks) — an active Goal with no step completed or scheduled in N days → suggest the next step, or offer to close it out.

Stay-in-touch needs a **contact-recency signal we don't store yet** — derived from Events/Notes involving the person plus a `people.last_contacted_on` touch (updated by a one-tap "log contact" and by accepting the suggestion). Exact design is open question Q8; the watcher ships after it's answered.

### Dials

Per-section agent level lives on `user_sections`, in the same Settings surface as section toggles (as D6 always said):

| Level | Scan cadence | Surfaces |
|---|---|---|
| **Off** | never | — |
| **Quiet** *(default)* | weekly | Section page Attend zone + Dashboard |
| **Active** | daily | + Today page (and notification channels, later) |

Default is Quiet, not Off: in-app-only and batched weekly is non-intrusive, and an agent nobody ever sees can't earn trust. The first suggestion a user ever sees carries an inline "tune this or turn it off" affordance pointing at the dials. FTUE (Q5) will later make the choice explicit.

Scheduling: a Solid Queue recurring job fans out per-user `AgentScanJob`s honoring the dials; fingerprints dedupe across runs.

### Privacy

Watchers scan a user's own data; cross-user coordination suggestions (the D8 "book us back-to-back" ambition) read other members' data exclusively through `visible_to` — the agent can never see, or hint at, more than the humans chose to share.

Notification channels (email/push) are deferred: self-hosted instances rarely have SMTP (the D15 argument), so the agent is in-app-only until that's designed. Logged as Q10.

---

## 4. Build sequence

1. ✅ **M2.1 — Anatomy + tools infra.** Act/Attend/Browse section page (Attend dormant), empty-state redesign, `Tool::Base` + registry, `tool_runs` + `ToolRunJob` + generic run page. Shipped with **Draft-a-dispute-letter** as the proving tool.
2. ✅ **M2.2 — First plan tool: Learn something.** Proved the plan seam with zero new schema: `Goals::BreakDown#plan!` (call + apply extracted from the breakdown job, shared by both) and the optional `brief` param. (Replaced the eviction Situation here — see the slate note.)
3. ✅ **M2.3 — Coverage slate**: doctor-visit prep, cancel-subscription, reconnect — each one declarative class on the shared Base contracts (DRAFT_FORMAT + `plan_goal!`), plus a `person` input kind.
4. ✅ **M2.4 — Situations**: "Plan a move" — the Q7 cross-section test, shipped as a plan tool with a rich brief and nothing else. Further Situations (lost-my-job, new-baby, eviction) are one class each, per demand.
5. ✅ **M3.1 — Suggestions core**: `suggestions` table (fingerprint-deduped, snooze/dismiss/accept with action payloads), Attend zone + Dashboard "From your assistant" feed, checkup-cadence watcher, weekly scan via Solid Queue recurring — everything hardwired to Quiet.
6. ✅ **M3.2 — Dials + watchers**: Off/Quiet/Active per section in Settings (`user_sections.agent_level`), honored by weekly/daily cadences (loudest dial among a watcher's sections wins); stay-in-touch (Q8 resolved: manual "Log contact" signal), renewal radar, goal stall.
7. **M3.3 — Garnish + reach**: ✅ the LLM-phrased Dashboard digest (phrasing only — deterministic facts in, two warm sentences out, silent failure). Remaining: cross-user coordination suggestions (needs its own design pass — shared-data semantics across household members), notification channels (Q10), Tier-B capabilities (Q9).

Still parked from before, unchanged: D14 leftovers (export, `model_profiles.api_key` encryption) slot in whenever — they don't block this sequence.

---

## 5. Milestone 4 — what remains (designed 2026-08)

Four items survived the first three milestones. Designs below; proposed decisions logged as **D21–D22** in `DECISIONS.md`.

### 5.1 Cross-user coordination (D21)

The D8 ambition ("book us back-to-back so we can carpool") turns out to need **no new machinery** — the visibility model was built for exactly this:

> **A cross-user watcher is an ordinary watcher whose queries use `visible_to(user)` scopes instead of user-owned scopes.**

Everything else follows from rules we already have:

- **Each member's agent speaks only to its own user.** There is no household-level agent; a coordination suggestion is one user's suggestion, produced by their own scan, over data they can already see. If both spouses share calendars, both may get the suggestion independently — that's correct, not a bug (each sees their own angle; fingerprints are per-user).
- **The suggestion body may reference only visible items.** This is enforced structurally: the watcher literally cannot query anything else. The agent can never leak, or even hint at, an unshared item (D9's guarantee, restated for prose output).
- **Staleness is handled the boring way.** If Alice accepts and the situation resolves, Bob's copy is dismissable; watchers never re-propose a fingerprint. No cross-user suggestion locking.

**First watcher: same-day sync.** The deterministic-first rule (D20) makes the fancy versions (location matching, "carpool-able") fuzzy, so v1 is the honest core: two household members with timed events on the same day within a few hours of each other, where at least one event is shared → heads-up to each sharing participant — "You and Bob are both out Thursday morning" — accept creates a "Coordinate Thursday with Bob" task. Location-aware upgrades come later, likely as LLM-phrased *garnish over the same deterministic signal*, never as the signal itself.

### 5.2 Notification channels (D22, resolves Q10)

The constraint: self-hosted instances rarely have SMTP (D15), and local-first means no push service account we own. Three channels, built in this order:

1. **Webhook** *(build first — trivial, most in-spirit)*: user pastes a URL in Settings; the agent POSTs a minimal JSON payload. This immediately covers ntfy (self-hostable push), Home Assistant, Matrix bridges — the ecosystem our users already run. One column, one job, huge reach.
2. **Web Push** *(the mainstream answer)*: browser push via VAPID keys generated per-instance at boot — no third party, works wherever the app is served over HTTPS. This is the channel for "normal" household members.
3. **Email, if configured** *(last)*: optional SMTP settings in instance Settings; when present, the weekly digest can go to inboxes. Never assumed, never required.

Delivery policy rides the dials: **only Active sections may notify** (Quiet stays in-app — that's what Quiet means), notifications are batched per scan (one message: "3 suggestions from your assistant", not three pings), and payloads carry **counts and titles only** — bodies stay in the app, since a lock-screen is not private by default.

Schema: `notification_channels` (user, kind, config JSON, enabled) + a `Notify` fan-out job called at the end of `AgentScanJob` for newly created Active-section suggestions.

### 5.3 D14 leftovers: export and key encryption

**Export** — the mission item: the user's life must be *portable*, not just stored.
- **Per-user, own-data-only** (D9: what's shared *with* you isn't yours to take): every primitive serialized as JSON-lines per model, plus the raw files of your documents, zipped.
- One button in Settings → background `ExportJob` → downloadable archive; the archive format is documented so anything can import it. (The full-instance backup story stays what it always was: copy the `storage/` volume.)

**`model_profiles.api_key` encryption** — Active Record Encryption (`encrypts :api_key`), with the self-hosting wrinkle solved at the entrypoint: the container's boot script generates AR encryption keys on first run if absent and persists them in the storage volume, so one-command install stays one command and existing plaintext rows are backfilled by a migration that re-saves them. No user action, no new secrets to manage manually.

### 5.4 FTUE (resolves Q5)

The gap: `/setup` creates the household, then drops you on an empty Dashboard. The vision line — a 22-year-old renter and a 60-year-old caregiver should see different apps — is one short, skippable flow (`users.onboarded_at`, redirect after first sign-in while nil):

1. **Pick your sections** — the seven top-level sections as cards, all pre-checked; unchecking writes explicit `user_sections` rows. No personas, no quiz — the sections *are* the personas.
2. **Set the assistant's voice** — one screen explaining the trust ladder in two sentences, with a single choice: suggestions **Quiet** (default, weekly, in-app) or **Off** for now; per-section dials are pointed at, not configured here.
3. **Connect a model** *(admin only, skippable)* — the existing provider picker, with the honest line that Organize works fine with no model at all.
4. **Bring your life in** — three buttons that already exist: import contacts, import calendar, upload a document. Ends on the Dashboard.

Every step skippable; the whole flow revisitable from Settings. Invited members get steps 1, 2, and 4 only.

### Build order

1. **M4.1** — FTUE (highest leverage per hour: every new instance sees it) + api_key encryption (small, overdue)
2. **M4.2** — Export (mission-critical trust feature; unblocks recommending the app to strangers)
3. **M4.3** — Webhook channel + Notify fan-out, then Web Push; email-if-configured last
4. **M4.4** — Same-day sync watcher (first cross-user coordination), then location/LLM garnish per demand

Q9 (Tier-B tool capabilities — live web data) stays deliberately parked until model-side browsing stabilizes or a first-party data pack makes sense; nothing above depends on it.
