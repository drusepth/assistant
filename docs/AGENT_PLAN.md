# AGENT_PLAN.md

Build plan for the **active agent** — what the Agent mode becomes beyond the
suggest-only milestone that is already built. ROADMAP.md §3 shipped the
proposing agent (M3.1–M3.3: the `suggestions` table, 32 watchers, the
Off/Quiet/Active dials, the phrased weekly digest) and M4 gave it reach
(notification channels, cross-user sync). This plan is the next rung of the
D6 trust ladder: an agent that doesn't just *point at* work but *arrives with
the work already done* — while changing nothing about who clicks.

Decisions here are logged as **D-agent-prepared-work,
D-suggestion-lifecycle, D-decision-links, D-agent-earned-dials** — all five
waves are **built** (2026-08); §9 records what the build changed about the
design.

---

## 1. Where the agent stands, and the gap

What "Active" buys today is *cadence and volume*: a daily scan instead of
weekly, the Today page, and the notification channels. The agent's abilities
are identical at every dial. Four gaps define this plan:

1. **Accepting a suggestion hands you homework.** The best accept today is a
   redirect to a prefilled tool form (`Suggestion#tool_action` →
   `new_tool_run_path`). The user still has to submit the form, wait for the
   run, review the result. The renewal-radar nudge about a lease ending in 60
   days *could have arrived with the response letter already drafted* — every
   piece needed (the tool, the inputs, the context) is already in the
   suggestion's action payload.
2. **Suggestions don't notice when the world resolves them.** Book the
   checkup yourself and the "you're due for a checkup" nudge sits in Attend
   until you dismiss it by hand. An assistant that keeps bringing up handled
   things reads as broken — the same trust rule that makes `Reminders::
   DispatchJob` retire anything more than a day late.
3. **The phone channels are one-way** (Q-sms-replies). A text can say "3
   suggestions from your assistant" but the user can't act from the phone;
   they have to find a browser, sign in, navigate. For the Active user —
   the one who *asked* to be notified — the loop never closes where the
   notification landed.
4. **The dials don't learn.** Quiet is the FTUE default and Active is buried
   in Settings; nothing ever tells the user who accepts every Health nudge
   that Active exists, and nothing ever offers to pipe down in a section
   whose suggestions get dismissed on sight. The FTUE copy already promises
   the fix: *"flip it on whenever the app has earned it."* Earning it should
   be the app's job to notice.

What this plan is **not**: the agent never gains a write surface beyond what
D20 granted. No primitive is created, edited, or completed without an
explicit click, and nothing is ever sent on the user's behalf (Q19 stays
parked, unchanged by anything here). The agent gets better at *having things
ready*; the user keeps *deciding*.

---

## 2. The thesis: prepared, not autonomous

> **"Active" means the agent arrives with the work already done — and still
> lands none of it until the click.**

The insight that makes this cheap: the suggest-and-apply pipeline and the
tool pipeline already meet at one seam. A watcher's `tool` action payload
(`{slug, inputs}`) is exactly a tool invocation the user hasn't clicked yet.
Preparation is the agent submitting that form on its own dime and parking the
result **on the suggestion**, so the accept click opens a finished draft
instead of an empty form. Same tool class, same prompt, same
`visible_to`-walled context, same review UI — the only new machinery is a
mode where tool output *waits* instead of landing.

This keeps every existing discipline intact:

- **D20** — the write surfaces are still `suggestions` plus the agent's own
  `tool_runs`. A prepared run owns its draft; nothing appears in Browse,
  Calendar, Today, or search until the user lands it.
- **Deterministic-first** — the model never decides *whether* to speak.
  Preparation only ever runs behind a suggestion a deterministic watcher
  already made. The LLM garnish rule survives; the garnish just got
  substantial.
- **Capability honesty** — with no model configured, preparation silently
  doesn't exist and every accept behaves exactly as today. Nothing errors,
  nothing apologizes.
- **Local-first** — preparation is the feature local models were made for:
  an agent that drafts ahead of you costs real money against a metered API
  and nothing at all against the Ollama box in the closet. The Settings copy
  should say so (D-local-first-models's argument, restated).

---

## 3. A1 — Suggestion lifecycle: retire what the world resolved

**New status: `resolved`** — retired by the world, distinct from `dismissed`
(retired by the user). The scan that proposes also retires.

`Watcher::Base` gains the inverse of `propose`:

- `def resolved?(suggestion)` — default `false`, so every existing watcher
  keeps today's behavior until it opts in. A watcher that implements it gets
  a **retire pass**: after `scan`, `AgentScanJob` iterates the user's
  actionable suggestions for that `watcher_slug` and resolves any the check
  returns true for. Same per-watcher error isolation as `scan` — a broken
  `resolved?` is `record_failure`d, never fatal.
- The checks are the watchers' signals, inverted, in SQL: checkup-cadence
  resolves when a matching Health event now exists upcoming; renewal-radar
  when follow-up work got attached or the renewal date passed; birthday-radar
  when the birthday passed; interview-ahead when a prep run exists or the
  interview happened; stale-task and goal-stall when the task/goal moved;
  pet-food-reorder when the shelf was refilled.
- One shared rule needs no per-watcher code: **a suggestion whose subject
  moment has passed retires**. A nudge about last Thursday's event is the
  agent reading as broken, exactly the D-reminders argument. Watchers whose
  fingerprints bucket by date (birthday, same-day sync, budget-pace months)
  get this for free from a `expires_on` key in the action payload, set at
  propose time, checked by the scan without consulting the watcher at all.

Fingerprint semantics are unchanged: `resolved`, like `dismissed`, never
re-proposes. If the condition genuinely recurs, the watcher's own fingerprint
bucketing (next quarter, next year) is what re-opens the conversation — the
same shape it already has.

Why this wave is first: it's model-free, it fixes a live trust papercut for
every user at every dial today, and A2 depends on it — a *prepared draft*
about a resolved situation is strictly worse than a stale nudge, so
preparation without retirement would be irresponsible.

---

## 4. A2 — Prepared work

### What is preparable

A suggestion is **preparable** when its action carries a `tool` payload whose
target is `kind: :draft` and whose prefilled `inputs` satisfy every required
input — i.e. the form the user would see has nothing left to ask. That
derivation is deterministic and needs no per-watcher code; a tool class can
opt out (`self.preparable = false`) if its runs are too slow or web-bound to
spend unbidden. Plan tools are not preparable in v1 (a prepared Goal plus its
breakdown graph is a much bigger deferred-landing surface — parked below),
and chat tools never are (a conversation can't be had in advance).

### When preparation runs

In `AgentScanJob`, after the scan and retire passes, **only for suggestions
whose loudest dial is Active** — the same `dial_for` gate that already
decides who may notify. Quiet keeps exactly today's behavior; the dial that
means "come to me" is the one that earns work done in advance. Guards, in
order: model configured, user's `prepare_work` toggle on (one user-level
switch beside the dials in Settings, default on — Active is already opt-in),
suggestion newly created this scan (never re-prepare a re-surfaced snooze),
and the budget below not exhausted.

**The budget:** `PREPARE_BUDGET = 3` preparations per user per scan,
counting attempts, not successes. Preparation is the first agent feature
that spends model tokens without a click, so it gets the email-triage
treatment: a hard per-scan cap, checked before the call, with the leftovers
simply staying unprepared redirects. Which three: scan order, no ranking
model — deterministic-first applies to spending priority too.

### How a prepared run works

- `tool_runs.origin` — `"user"` (default) or `"agent"`. Agent runs render
  labeled ("prepared by your assistant") everywhere runs appear.
- New status **`prepared`**: the run executed its model call, but its landing
  helpers (`create_note` / `create_task` / `create_event` / `record`) wrote
  **landing intents** into `run.output["landings"]` — typed hashes, exactly
  the arguments they would have passed — instead of rows. One mode flag in
  `Tool::Base`, consulted by the landing helpers; tool classes change *zero*
  lines, which is the point of routing preparation through the same classes.
- `suggestions.tool_run_id` (nullable) points at the prepared run. The
  suggestion card gains a "prepared" chip; its accept label becomes "Review
  draft".
- **Accept** redirects to the run's show page in review mode: the draft
  body, the follow-ups it wants to create, and two buttons. **Save** replays
  the landings as real primitives (`ToolRun#land!`, status → `done`,
  suggestion → `accepted`) — this click is the D20 accept, materially
  identical to the user having run the tool themselves. **Discard** dismisses
  the suggestion and the run together (status → `discarded`). Until one of
  those clicks, the suggestion stays `pending` — looking is not accepting.
- **Failure degrades to today.** A prepared run that fails (`Llm::Error`,
  budget, opt-out) leaves the suggestion exactly as M3 built it: a redirect
  to the prefilled form. `record_failure`, no user-visible apology. The
  feature is pure upside or invisible.
- **Staleness rides A1.** When a suggestion retires — resolved, dismissed,
  or expired — its prepared run is discarded with it. A draft letter about a
  bill that got paid must not outlive the nudge that occasioned it. Prepared
  drafts also never survive re-preparation: there is at most one run per
  suggestion, ever, because the suggestion fingerprint already guarantees at
  most one proposal per subject.

### What the user sees

Nothing new to configure beyond the one toggle. The visible changes are: some
Active-section suggestions arrive with a "prepared" chip and open straight
into a finished draft; Settings' dial block grows one transparency line
("this week: N scans, M drafts prepared" — derived from `tool_runs` where
`origin = "agent"`, no new bookkeeping); the run history shows agent runs
labeled as such. The first prepared suggestion a user ever sees carries the
same inline "tune this or turn it off" affordance the first plain suggestion
did — pointing at the `prepare_work` toggle.

---

## 5. A3 — Decision links: close the loop where the notification landed

The Q-sms-replies question, resolved toward its **signed-link** design — and
simplified by one honest observation: once the decision is authenticated by a
real session (which that entry already concluded it must be), the link needs
to *identify*, not *authorize*, so single-use ceremony buys nothing.
Accept/dismiss are idempotent — a second click on a non-pending suggestion
is a no-op — so a replayed link is harmless.

- Every notification batch appends one URL: `/assistant/decisions/:token`,
  where the token is a signed (`ActiveSupport::MessageVerifier`-style,
  purpose-scoped), **expiring** (7 days) list of the batch's suggestion ids.
  No new table.
- The page requires a signed-in session — the token renders nothing to an
  unauthenticated visitor beyond the sign-in redirect, so a leaked or
  carrier-logged URL still exposes nothing (the D22 lock-screen rule,
  extended to the link the lock screen carries). It shows only suggestions
  that are still actionable *and belong to the session's user*, each with
  the full body (we're in-app now — bodies are allowed) and one-tap
  accept / snooze / dismiss.
- Works identically on every channel — webhook, Web Push, email, SMS,
  Signal — because it's just a URL in the payload. On the phone kinds the
  URL counts toward the two-segment `TEXT_LIMIT`, so the route stays short
  and the token is the compact signed id, not a JSON blob.
- Reply-to-answer (inbound SMS parsing) stays rejected for the reasons the
  Q entry gave: it needs a publicly reachable inbound endpoint, and sender
  ID is spoofable. The signed link works behind NAT on every provider
  including the gammu modem — the mission-true channel keeps parity.

With A2, this is where prepared work pays off end-to-end: the text says a
draft is ready, the tap opens the review page, and the whole
notice-review-save loop happens on the phone in under a minute.

---

## 6. A4 — Earned dials: the agent tunes itself, by asking

Two symmetric meta-suggestions from one sectionless meta-watcher
(`dial_tuner`, weekly, model-free):

- **The upgrade offer.** A section on Quiet where the user accepted ≥3
  suggestions within 90 days → one `insight`: "You've used most of what I
  suggested about Health. Want me to check daily and notify you?" Accept
  sets that section's dial to `active` — via a new `agent_level` action key
  in `Suggestion#materialize` (validated against `AGENT_LEVELS`, only for
  the suggestion's own user's `user_sections` row). Fingerprint
  `dial_tuner/upgrade/<section>` — offered **once ever** per section; a
  dismissal is a permanent answer, which is what makes the offer polite.
- **The humility offer.** A section where the last 6 suggestions were all
  dismissed and none accepted in 6 months → "Should I stop bringing these
  up?" Accept sets the dial down (`quiet` → `off`, `active` → `quiet`).
  Fingerprint bucketed by year, so the offer can recur — going quieter must
  stay easy — but never nags within one.

The suggestions are tagged with the section they're about (`sections:
[s.slug]`), so each shows up in that section's own Attend zone, where the
context makes the question legible.

**The FTUE stays Quiet/Off, deliberately.** Onboarding never offers Active
(the existing seam in `save_agent_voice` is correct): a first-run user has no
basis to want daily notifications from an app that hasn't shown them
anything. The upgrade offer *is* the missing FTUE step, delivered at the only
moment it can be answered honestly — after the app has earned it, exactly as
the step-2 copy promises.

---

## 7. A5 — Garnish, and what stays parked

- **Daily brief for Active users.** The digest recipe (`Users::WeeklyDigest`:
  deterministic facts in, two warm sentences out, silent failure) currently
  runs weekly for everyone. Users with ≥1 Active section get it regenerated
  by the daily scan too — the Dashboard greeting stays current for exactly
  the people who asked the app to be daily. No new prompt, no new surface,
  one condition in `AgentScanJob#generate_digest`.
- **Prepared plan tools** — a Goal and its breakdown, landed as one deferred
  graph. Wants the A2 landing-intent seam proven first; the breakdown
  pipeline's `plan!` already separates call from apply, so the seam is
  plausible. Build when a plan-tool suggestion (goal-stall's "suggest the
  next step") demonstrably suffers from the form hop.
- **Q-agent-chat-openers** *(new open question)* — may the agent open a
  conversation? The tutor noticing a review backlog and starting the session
  itself is the natural end of "the app comes to the user", but an unsolicited
  chat turn is a stronger interruption than any suggestion card, and D33's
  ephemeral transcripts complicate "picking up where it left off". Parked
  until chat has streaming and real daily use.
- **Q19 (outbound action)** — unchanged and untouched. Nothing in this plan
  sends, submits, or transacts. The trust ladder's next rung after this plan
  is *that* consent design, and it should be climbed only after prepared
  work has run in houses for a while.

---

## 8. Trust and threat model

- **D20, restated for preparation:** the agent's write surfaces are
  `suggestions` and its own `prepared`/`discarded` `tool_runs`. Landing
  intents are data, not rows. The one genuinely new resource the agent
  spends without a click is **model tokens** — bounded by the Active-dial
  gate, the `prepare_work` toggle, and the hard per-scan budget, and
  accounted for in the Settings transparency line. On a self-run model the
  cost is zero, and the UI says so.
- **Privacy at the notification boundary is unchanged:** payloads carry
  counts and watcher-written titles. Prepared drafts — which contain model
  prose over owned documents — never ride a notification; they are only
  ever rendered in-app, behind the session, like every other primitive.
  The decision link identifies, the session authorizes.
- **Hostile input:** a prepared run reads exactly the context the same tool
  reads when the user invokes it — `visible_to`-scoped, char-budgeted, and
  (for the email tools) already covered by EMAIL_PLAN's threat model. Model
  output in a prepared run lands nowhere until review; injection's best case
  is a bad draft the user reads before saving, which is the same best case
  it already had.
- **Cross-user:** preparation inherits D21 structurally — a prepared run for
  a same-day-sync suggestion queries through `visible_to(user)` because the
  tool class does; there is nothing extra to enforce.
- **No model configured:** A1, A3, and A4 are fully model-free; A2 and the
  A5 brief silently don't exist. The agent's deterministic core never
  regresses.

---

## 9. Build order

All five waves are **built** (2026-08). Each landed green and independent,
in this order:

1. ✅ **A1 — Lifecycle**: `resolved` status + `expires_on` +
   `Watcher::Base#resolved?`/`retires?` + the retire pass, with inverse
   checks for nine watchers. Model-free; prerequisite for A2.
2. ✅ **A2 — Prepared work**: `tool_runs.origin` + `prepared`/`discarded`
   statuses + landing intents + `land!` + review UI + budget +
   `prepare_work` toggle + transparency line. The flagship.
3. ✅ **A3 — Decision links**: the signed-token decision page + the URL in
   every channel payload. Closes Q-sms-replies' loop.
4. ✅ **A4 — Earned dials**: `dial_tuner` + the `agent_level` action key.
5. ✅ **A5 — Daily brief** for Active users; the parked items wait for
   their moments.

### What the build changed about the design

Three things came out different, and each is the more defensible version:

- **The no-side-effects guarantee moved from the tools to the runner.**
  §4 described landing intents as a mode the `Tool::Base` helpers honor,
  which is true but would have made the guarantee a rule every future tool
  had to follow — and four tools already create primitives outside those
  helpers. `Agent::Prepare` now runs the whole call inside a transaction it
  always rolls back, so the property holds for tools that have never heard
  of preparation: their writes are undone, and having staged no intents
  they prepare nothing at all and degrade to the plain redirect.
- **The decision token is packed by hand.** §5's signed token, built the
  obvious way with Rails' `expires_in:`/`purpose:` metadata, measured 162
  characters — a 212-character URL against a 300-character SMS bound, which
  would have left almost no room for the message. Packing `expiry.ids`
  ourselves and deriving the key from the purpose gets the URL to 124.
  The summary now yields space to the link rather than the link being
  truncated, since a broken URL is worse than a short sentence.
- **An unparseable fingerprint means "can't say", not "handled".** A1's
  retire checks read their subject back out of the fingerprint, and the
  first draft treated a subject it couldn't find as resolved. That is right
  for a deleted row and badly wrong for a fingerprint format that changed —
  it would silently retire every live nudge of that watcher on the next
  scan. The parse failing and the record being gone are now different
  answers.

## 10. Schema summary

| Change | Where | Wave |
|---|---|---|
| `resolved` status value | `suggestions.status` (string enum — no migration) | A1 |
| `expires_on` action key | `suggestions.action` JSON (no migration) | A1 |
| `tool_run_id` (nullable FK) | `suggestions` | A2 |
| `origin` (`user`/`agent`, default `user`) | `tool_runs` | A2 |
| `prepared` / `discarded` status values | `tool_runs.status` (string enum) | A2 |
| `landings` key | `tool_runs.output` JSON (no migration) | A2 |
| `prepare_work` boolean, default true | `users` | A2 |
| `agent_level` action key | `suggestions.action` JSON (no migration) | A4 |

No new tables. The seams this plan leans on — `Suggestion#materialize`,
`Watcher::Base#propose`, `AgentScanJob#dial_for`, the `Tool::Base` landing
helpers, `Notifications::Deliver`'s payload assembly — all exist and none
changes contract; every addition is a new mode or key beside them.
