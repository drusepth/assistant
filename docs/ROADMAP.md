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

- **Plan tools** create a Goal plus 3–10 scheduled, multi-tagged Tasks/Events — by riding the existing D17 `BreakDownGoalJob` pipeline with a tool-specific system prompt and context. **Situations (D7) are exactly plan tools**: "eviction notice" is a plan tool with a rich prompt that spawns Rights + Money + People-tagged work. The Q7 pressure test is therefore Milestone 2's pilot, not a separate detour.
- **Draft tools** produce a reviewable text artifact — a dispute letter, a doctor-visit prep sheet, a study explainer — stored as a draft Note or Document linked to the run, optionally with follow-up Tasks/Events (e.g. "mail by Friday" when a letter has a deadline).

The eviction Situation deliberately composes both (a plan *and* a drafted answer letter), which is why it's the pressure test.

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

Ordered to prove the frame, then spread coverage — roughly one tool per section:

1. **Rights → Disputes: "Draft a dispute letter"** *(draft)* — the mission's heart; reads a chosen Document (bill, denial, collection notice) + one line of user intent → formal letter + deadline Task/Event. First tool built; ships with the infra.
2. **Situations: "Eviction notice"** *(plan + draft)* — the Q7 pressure test; rich breakdown prompt spawning multi-tagged Tasks/Events plus a drafted response letter.
3. **Health: "Doctor-visit prep"** *(draft)* — reads Health-tagged items → question list + one-page history summary to bring to the appointment.
4. **Education: "Learn something"** *(plan)* — study plan as Goal + scheduled Tasks; steps can expand into explainer Notes on demand.
5. **Money → Subscriptions: "Cancel this subscription"** *(draft)* — cancellation letter/script + a reminder Task.
6. **People: "Reconnect"** *(draft)* — reads a Person + what's known about them → message draft + catch-up talking points. Deliberately seeds the Milestone 3 stay-in-touch watcher (its accept action runs this tool).

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

1. **M2.1 — Anatomy + tools infra.** Act/Attend/Browse section page (Attend dormant), empty-state redesign, `Tool::Base` + registry, `tool_runs` + `ToolRunJob` + generic run page. Ships with **Draft-a-dispute-letter** as the proving tool.
2. **M2.2 — Eviction Situation** as the first plan tool — this *is* the Q7 pressure test, now riding tool infra.
3. **M2.3 — Coverage slate**: doctor-visit prep, learn-something, cancel-subscription, reconnect.
4. **M3.1 — Suggestions core**: `suggestions` table, Attend zone + Dashboard attention feed, checkup-cadence watcher, everything hardwired to Quiet.
5. **M3.2 — Dials + watchers**: dials in Settings, remaining watchers (incl. Q8's contact-recency design), weekly/daily scheduling.
6. **M3.3 — Garnish + reach**: LLM-phrased digest on the Dashboard, cross-user coordination suggestions, revisit notification channels (Q10) and Tier-B capabilities (Q9).

Still parked from before, unchanged: D14 leftovers (export, `model_profiles.api_key` encryption) slot in whenever — they don't block this sequence.
