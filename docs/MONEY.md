# MONEY.md

Design for the **Money section buildout, centered on budgeting**: the spending
substrate, the budget itself (making it, living inside it, staying faithful to
it), and the money coach — the assistant you talk to *before* you buy the thing
you shouldn't. This is the section deep-dive for Money the way `HEALTH.md`,
`PEOPLE.md`, and `CAREER.md` are for theirs, and the build plan in one document.

Proposed decisions are logged as **D-spending-mirror**, **D-budget-envelopes**,
and **D-money-coach** in `DECISIONS.md` (kebab slugs per CLAUDE.md conflict
hygiene; provisional until the build passes prove them).

---

## 1. Why this is a headline feature

PRODUCT.md already names the stakes: for the target user, **cash flow is the
daily battle** — assets are the goal, flow is the fight. And the existing tool
wave attacks money lost at *deadlines* (unappealed denials, unclaimed
benefits); this buildout attacks money lost in *drift* — the slow leak of
unplanned spending, forgotten subscriptions, and quiet price hikes that no
letter can recover.

The market failure is a mission bullseye:

- **Budgeting is rented.** Mint is dead; YNAB is ~$110/yr; Monarch ~$100/yr.
  The people who most need a budget are being charged a subscription to keep
  one — and the data lives on someone else's server, monetized. A self-hosted,
  free, private budget is exactly the "service stack the wealthy already get"
  argument: the wealthy have money managers; everyone else gets upsold apps.
- **The coach half is the part money apps can't ship.** A meter that turns red
  is cheap; someone to *talk to* at the moment of temptation — who knows your
  budget, your goals, and your hourly wage, and answers in ten seconds without
  judgment — is what a human money manager actually provides. With the owned
  memory layer, that's a chat tool, not a fantasy.
- **It compounds everything already built.** Subscriptions gets its audit
  (feeding `cancel_subscription`), Bills gets its promised price-hike
  detection, Debt gets a payoff planner, the Career comp timeline gets its
  "bank-deposit signal" consumer, and the email mirror's parked
  receipts-to-Money linkage gets a destination.

**Value without AI holds** (the D13 principle): the ledger, the envelopes, and
the meters are fully deterministic — a household with no model configured still
gets a working budget. The model adds drafting the budget, narrating the
review, and the coach.

### What exists today

Money is seeded subsection tiles (Budget, Debt, Taxes, Assets, Bills,
Subscriptions, Benefits) over an empty pool, plus the letter-family tools
(`decode_letter`, `debt_collector_response`, `benefits_screener`,
`cancel_subscription`, `negotiation_prep`) and the renewal-radar watcher.
Nothing tracks spending; nothing is a budget. There is no Money panel (D37),
so the section page is the generic browse grid.

---

## 2. The spending substrate (D-spending-mirror)

A budget without spending data is a wish list. The substrate question — where
do transactions come from, and where do they live — is the hard one, and the
architecture already answered half of it: **D-mirror-layer names transactions
as a future mirror source.** Bank transactions are exactly what the mirror
pattern was built for: high-volume, derived from an external source of truth,
re-importable, outside the primitive pool, owner-private with no `visible_to`
path to leak.

### 2.1 The import ladder (granted data over a manual floor)

The D-career-signal ladder, applied to spending — and the same hard rule:
**inference never, and no connection we'd become a landlord through.** Plaid
and its class of aggregators are rejected for v1 on the D27 argument: a paid,
US-centric, terms-encumbered chokepoint between the user and their own bank is
the opposite of the mission. (Self-hostable bridges are the open question —
see Q-bank-connections.)

1. **Manual quick-log — the always-available floor.** One line on the Budget
   panel: amount + what ("14.50 lunch"). D16 discipline: the categorizer files
   it (rules first, then keywords, then model garnish — §2.4); the user types
   two things. Works on day one with zero imports and zero model.
2. **Statement files — the workhorse.** Every bank offers CSV/OFX/QFX/QIF
   export. The uploaded statement is an ordinary vault **Document** (Money +
   the account's subsection tags) — the durable, exportable artifact — and a
   parser fans its rows into the transaction mirror. Re-importing an
   overlapping statement is the *normal case* and dedupes cleanly (§2.3).
   - **OFX/QFX** parse deterministically (small hand parser, same
     plain-stdlib idiom as `Dav::Client`); they carry stable bank transaction
     ids — the best dedupe key.
   - **CSV needs a mapping step**: bank CSVs disagree about everything. First
     import from an account shows a column-mapping form (date / description /
     amount, or debit+credit columns; date format sniffed, confirmable); the
     mapping is saved per account so the second import is one click.
3. **Email receipts — the mirror-to-mirror signal.** The parked EMAIL_PLAN
   follow-on lands here (build pass B5): deterministic receipt detection over
   the email mirror surfaces "looks like a purchase" *suggestions* that log a
   transaction on accept. Signal, suggestion, click — never an auto-write.
4. **Direct bank connections — deferred** (Q-bank-connections), with the D27
   shape as the only acceptable one: open protocols or a stateless,
   self-hostable bridge, never a mandatory paid intermediary.

### 2.2 Schema

Primary database (owned config, small, exported with the life file):

- **`spending_accounts`** — user, name ("Chase checking"), kind
  (`checking`/`credit`/`cash`), `last4` (display only — full account numbers
  are never stored), `csv_mapping` (JSON, saved on first import). The
  `linked_accounts` precedent: config in primary, firehose in mirror.
- **`budget_categories`** — §3.
- **`spending_rules`** — §2.4. User-authored config, primary database — the
  same argument that put `email_sender_rules` there.
- **`households.currency`** — one new column (ISO code, default `"USD"`,
  admin-edited on the household profile page). It clears the
  D-household-profile bar: its named consumer is every money formatter in the
  app. Free text over an enum, per the D34 audience argument.

Mirror database (D-mirror-database; high-churn, derived, elastic):

- **`spending_transactions`** — soft `user_id` and `spending_account_id`,
  `occurred_on`, `amount_cents` (signed; negative = money out), `descriptor`
  (raw), `merchant` (normalized — deterministic cleanup of processor noise:
  strip card suffixes, `SQ *`/`TST*` prefixes, city/state tails),
  soft `budget_category_id`, `categorized_by`
  (`rule`/`keyword`/`model`/`user`), `source`
  (`statement`/`manual`/`email_receipt`), `external_id` (the OFX FITID when
  present), `fingerprint`, soft `document_id` (the statement it came from),
  `transfer` (boolean — §2.3). Indexed by (user, occurred_on) and
  (user, merchant).

**The export carve-out, stated plainly.** Email's mirror is excluded from the
D14 export because the mailbox remains the truth forever. Banks are not
mailboxes: portals age statements out after 12–24 months, and manual and
receipt-sourced rows have no backing document at all — so for spending, the
mirror is often becoming the *only* copy. The export therefore gains one
`spending.csv` (all transactions, plain columns). The mirror doctrine
otherwise holds unchanged: primitives never reference mirror rows, deletion
is per-row and honored on re-import (the tombstone lesson), and re-importing
a kept statement Document rebuilds everything statement-sourced.

**Retention: keep everything, by default and by design** — the opposite of
email's 90-day window, decided for the opposite reason: transaction rows are
tiny, and years of history is where trends, price-hike detection, and honest
budget targets come from. No pruning job.

### 2.3 Dedupe and transfers

- **Dedupe**: `external_id` per account wins when present (OFX); otherwise a
  fingerprint of (account, date, amount, normalized descriptor). Same
  fingerprint = same transaction, skipped silently with a per-import count
  shown ("212 rows, 38 already known"). A user-deleted row's fingerprint is
  remembered (the mirror tombstone pattern) so re-import doesn't resurrect it.
- **Transfers**: paying a credit card from checking is not spending, and
  double-counting it is the classic budget-app trust-killer. Deterministic
  pass at import: opposite-signed same-amount rows within a few days across
  the user's own accounts are flagged `transfer` (both sides), excluded from
  all spending math, visible in the ledger with a "transfer" chip the user
  can toggle when the heuristic is wrong.

### 2.4 Categorization: rules before model, always

The D-email-monitoring feedback loop, verbatim in spirit:

1. **`spending_rules` decide first** — user-owned rows (`matcher` substring
   against merchant, `budget_category_id`), created almost entirely by
   one-click feedback: recategorizing any transaction offers "always file
   <merchant> here," which writes the rule. Week-one misfires become week-two
   accuracy through rules, not through hoping the model guesses better.
2. **A small keyword table covers the obvious** (grocery chains, fuel,
   utilities patterns) — code, zero tokens, conservative: unmatched stays
   uncategorized rather than wrong.
3. **Model garnish for the leftovers, batched and validated.** After an
   import, one call categorizes the remaining uncategorized rows (batch of
   ~40 merchant strings + the user's category list). **Validated labels
   only** (the mirror hostile-input rule: descriptors are external text) — the
   model returns category names checked against the user's actual list;
   anything else is dropped, never stored. No model configured → rows stay
   uncategorized and everything still works.

`categorized_by` records provenance; a `user` categorization is never
overwritten by any automatic pass (D16's hand-set rule).

### 2.5 The ledger surface

`/spending` — the mirror browse page (the `/mail` idiom): filterable by
account, month, category, uncategorized-only; each row shows date, merchant,
amount, category chip (click to recategorize → rule offer), transfer toggle,
delete (tombstoned). Entry points: the Money panel, the Budget panel, and each
`spending_account` row in Settings. Like all mirror surfaces it is
owner-only — structurally, not by policy.

---

## 3. The budget itself (D-budget-envelopes)

### 3.1 What a budget is here

**A budget is a set of user-owned monthly envelope targets over spending
categories.** Not zero-based-or-bust, not a spreadsheet of accounts — the
simplest model that supports "did I stay inside the plan": categories, each
with a monthly target, grouped **Needs / Wants / Savings & debt** (the 50/30/20
frame as furniture, never as a mandate), plus optional **Income** entries so
the plan can show "planned to keep $X."

- **`budget_categories`** — user, name, `group`
  (`income`/`needs`/`wants`/`savings_debt`), `monthly_target_cents`,
  `position`, `archived_at`, `target_set_by` (`user`/`tool` — the hand-set
  guard). Categories double as the categorization target (§2.4): one list,
  two jobs — no parallel taxonomies.
- **Month math is computed, never stored.** `Money::MonthSummary` (a plain
  service, the `Health::CareRadar` idiom: derived view over the ledger, zero
  new state) answers everything per month: per-category actuals vs. target,
  group subtotals, pace (spent-fraction vs. month-fraction), unbudgeted
  spending, planned-vs-actual kept. A derived view can never disagree with
  the ledger it reads.
- **Rollover is deliberately out of v1.** Envelope-carryover math is where
  budget apps get complicated and users get confused; month boundaries reset
  cleanly, and the month-close review (§5) is where a surplus or overrun gets
  *talked about* instead of silently banked. Revisit on demand.
- **Privacy: budgets are per-user and private, full stop.** `budget_categories`
  are not primitives — no `Visible`, no grants, no cross-user read path, and
  the ledger they measure is mirror-resident (structurally unshareable). A
  couple budgeting jointly is real and deferred honestly (Q-household-budget)
  rather than half-shipped through the grants system it doesn't fit.

### 3.2 Making it: `build_my_budget` (Budget + Money, draft)

The tool that turns "I should really budget" into a budget in two minutes.

- **Inputs**: none required when spending history exists. With a thin ledger,
  three optional fields carry the intake (D16: 0–2 questions is the ideal,
  three is the cap): monthly take-home ("roughly"), rent/mortgage, and one
  free line ("anything big going on — new baby, paying down cards").
- **Context**: code-computed aggregates from the last 90 days of ledger —
  per-merchant and per-category monthly averages, recurring charges — as a
  compact block. **The model never sees raw transaction rows**; code
  aggregates, the model proposes. Plus `section_context(%w[money])` and the
  D34 region line.
- **Output contract**: `{"budget": {"categories": [{"name", "group",
  "monthly_target", "why"}]}, "summary": {"title", "body"},
  "follow_ups": [...]}`. Code validates hard: group from the enum, targets
  numeric and non-negative, category count capped (~15), names deduped
  against existing categories case-insensitively.
- **Lands, suggest-and-apply (the D17 discipline exactly)**: new categories
  created with targets; existing categories *never* have a hand-set target
  overwritten (`target_set_by` guards); pruning any category is one click.
  Plus one **"Your budget, explained" Note** (why each number, where it came
  from — "groceries $520: your 3-month average is $487") filed under Budget,
  and ≤2 follow-up Tasks ("import your credit-card statement so the picture
  is complete").
- **Honesty guardrails**: history-derived numbers cite the computed average
  they came from; intake-derived numbers say "starting point — tune after a
  month of data." No invented precision. Re-running later reads
  actuals-vs-targets and proposes *adjustments* through the same
  suggest-and-apply gate — "tune my budget" is the same tool, not a second
  one.

### 3.3 Living in it: the panels (D37)

Two panel classes, two partials, registry edits only — the Money buildout
touches none of the shared section files.

- **`Sections::Panels::Money`** (the section page) — the money map:
  this-month hero (spent vs. planned overall, days left, one pace sentence),
  three group bars, the quick-log line, an import button, and the subsection
  browse tiles it already gets — now with real signal ("Budget: 64% through
  the month, on pace"). `hidden_tool_slugs` curates the Act zone (the letter
  family stays; budget tools appear as panel cards with better context).
- **`Sections::Panels::Budget`** (the subsection page) — the envelope board:
  per-category meters (target, spent, remaining, pace tick — quiet color
  shift only when meaningfully over-pace: meters inform, they don't scold),
  month picker (historical months render read-only from the same
  `MonthSummary`), quick-log capture, uncategorized-count chip linking to
  `/spending`, and the empty state as front door: no categories → the
  "Build my budget" card leads; no ledger → the import/quick-log invitation
  leads. No signal, no shame — an empty budget page never guilt-trips.

---

## 4. Staying faithful: the watchers

Deterministic SQL over the ledger and `budget_categories` — the D20 rule, with
the email precedent extended: watchers may read mirrors, and **no signal means
no nudge** (a user with no imports gets a silent agent and an inviting Budget
page, never a hollow scold). All ride Money's existing dials
(Off/Quiet/Active), fingerprint-deduped, digest-eligible.

- **`budget_pace`** — a category crosses pace meaningfully (spent-fraction
  exceeds month-fraction by a margin, e.g. ≥85% spent with ≥10 days left),
  fingerprinted per category per month — one nudge per envelope per month,
  ever. "Groceries is at $470 of $520 with 12 days left." Accept opens the
  money coach with the category preloaded ("let's find the next two weeks'
  plan"); dismiss means dismissed (fingerprints never re-propose).
- **`new_recurring_charge`** — a merchant hits its third roughly-monthly,
  roughly-equal charge with no prior history → "Looks like a new
  subscription: <merchant>, ~$12.99/mo." Accept offers two doors: file it
  (a Subscriptions-tagged Note + renewal Event — now renewal-radar fuel) or
  open `cancel_subscription` prefilled.
- **`price_hike`** — a known recurring charge's amount steps up cycle-over-
  cycle (beyond a small tolerance) → "Your <merchant> charge went from $15.49
  to $17.99." Accept routes `negotiation_prep` (bills mode) or
  `cancel_subscription`. This is the Bills subsection's PRODUCT.md promise,
  shipped — and it needs nothing but the ledger and arithmetic.
- **`month_close`** — the first scan after a month rolls over with any budget
  activity → "Your January review is ready." Accept runs `spending_review`
  (§5) prefilled to that month. Quiet-dial-friendly: one suggestion a month.

Deliberately unbuilt: low-balance warnings (needs balance data we don't
reliably have), any "you spent money on X" judgment nudge (the D36 lesson: an
assistant that nags gets turned off — pace facts only, never commentary), and
any LLM in the signal path (garnish phrases, never decides).

---

## 5. The coach (D-money-coach)

The half that makes this a money *manager* rather than a spreadsheet. Two
tools: a conversation for decisions and feelings, a review for facts and cuts.

### 5.1 `money_coach` — "Talk it through" (Money + Budget, **chat**)

The D29/D32 pattern at full strength: chat kind, mode presets as quick
replies (the `check_in` idiom), owned-context system prompt, explicit-save
recaps, ephemeral transcripts (D33 — for money-stress conversations, the
delete button is a trust feature).

- **Modes** (quick replies on the opening message): **"I want to buy
  something"** · **"Help me spend less"** · **"I'm stressed about money"** ·
  **"Plan this month"** — free text always honored.
- **Context** (code-built, compact): the current `MonthSummary` snapshot
  (categories, targets, month-to-date, pace), active Money-tagged Goals,
  recent coach recap Notes (continuity — it remembers you're saving for the
  deposit), the D34 region line, and — only when the D-career-signal comp
  timeline has data — an hourly-wage line, source named, so the coach can
  offer the honest frame: "that's about 6 hours of work." No comp signal, no
  hours math — never estimated (the ladder's rung-3 rule).
- **The buy-decision protocol** (system prompt, for mode 1): ask before
  telling — what is it, what does it cost, which envelope would it come from,
  what would it displace; surface the tradeoff against the user's own stated
  goals, in their own numbers; offer the 48-hour wait as a move, never a
  rule; and **when the user says "I'm buying it anyway," help them fit it in
  gracefully** — adjust the envelope math, no parting shot. The user
  disposes; a coach who sulks gets closed and never reopened.
- **Tone contract**: never shame, never moralize, never catastrophize;
  curiosity over verdicts; the user's values set the goals, the coach defends
  the user's *own stated plan* back to them — that's the whole job.
- **The hard guardrail, in code**: a code-appended opening notice (the D32
  crisis-notice mechanism — visible in the transcript, never sent to the
  model): *"I'm a budgeting coach, not a licensed financial advisor — for
  investment, tax, or legal decisions, talk to a professional."* The system
  prompt forbids recommending specific investment products, securities, tax
  strategies, or credit products; and when the conversation sounds like debt
  distress (collectors, can't-make-rent), it steers warmly to nonprofit
  credit counseling (NFCC-style services) and to the app's own Rights/Debt
  tools — the 988 pattern, translated: the heaviest moments route to humans
  and to the letters that actually stop harm.
- **Recaps**: "Save a recap" lands the decision or the plan as a Note under
  Money ("Decided to wait on the espresso machine until March — here's why").
  Recaps are what future sessions read. No auto-writes, ever.

### 5.2 `spending_review` — "Where's my money going?" (Money + Budget + Subscriptions, draft)

The what-to-cut tool, and the month-close ritual.

- **Inputs**: `month` (defaults to last full month); `focus` (optional free
  line — "why was December so bad", "find me $200/month").
- **Context**: code-computed aggregates only (the §3.2 rule): category
  totals vs. targets, top merchants, recurring-charge table with
  cycle-over-cycle deltas, month-over-month movement. The model narrates and
  prioritizes; **every number in the output arrived in the input** — the
  prompt forbids invented amounts, and the review says what its numbers are
  ("from your imported statements through Jan 31").
- **Output contract**: `{"review": {"title", "body"}, "cuts": [{"what",
  "monthly_amount", "how", "tool_slug"?}], "next_tools": [...],
  "follow_ups": [...]}` — cuts capped at 5, each traceable to an aggregate.
- **Lands**: the review Note (the month in plain language: what went to
  plan, what didn't and *why it might have* — asked, not asserted; the
  recurring-charge audit; 3–5 cut candidates with realistic monthly numbers
  from actual data); **next-step cards via D28 routing** — `cancel_subscription`
  prefilled with the subscription's name, `negotiation_prep` prefilled for
  the hiked bill, the coach for the "help me actually do this" conversation;
  ≤3 Tasks. This is the composed payoff: audit → one click → the cancellation
  letter — the full stack from mirror to draft in two clicks.

### 5.3 Later coach family (B5, on demand)

- **`debt_payoff_plan`** (Debt + Budget, plan) — debts as stated by the user
  (balances, APRs, minimums — free text or a statement Document), method
  explained honestly (avalanche saves interest, snowball keeps you going —
  the user picks), lands a Goal + monthly payment Tasks/Events through the
  shared breakdown with a rich brief. Projections phrased as approximate;
  the model restates the user's numbers, it doesn't do compound-interest
  theater.
- **Savings goals need no new machinery**: "save $2,000 for the deposit" is
  an ordinary Goal the coach already reads via context — the lens model
  working unchanged. A progress-vs-ledger tie-in (auto-detecting transfers to
  savings) is garnish for later.

---

## 6. Privacy, hostility, honesty

- **Money data is maximally sensitive; the walls are structural.** The ledger
  is mirror-resident: no `Visible`, no `Sectionable`, no grants path —
  unshareable by construction (the D-mirror-layer claim, second source). The
  budget is per-user primary-DB config with no read path but its owner.
  What *is* shareable is what the user deliberately makes a primitive: review
  Notes, the budget-explained Note, coach recaps — normal grants, normal
  choices (D9).
- **Hostile input travels with the pattern.** Statement descriptors and
  receipt text are external text that reaches the model: categorization is
  validated-labels-only (§2.4), review numbers are code-built aggregates,
  chat context blocks are data-not-instructions framed, and no model prose is
  ever a notification payload (D22 titles-not-bodies already covers the
  rest).
- **Never stored**: full account numbers, credentials of any kind (statement
  import is files, not logins), balances we didn't parse, and any inferred
  judgment about spending ("impulsive") — the coach may *say* things in a
  transcript that evaporates (D33); the durable record is only what the user
  saves.
- **Capability honesty**: everything here is Tier A. No live prices, no
  market data, no "current best savings rate" — the coach reasons over owned
  data and says so. Q9's flag someday relaxes this; nothing depends on it.

---

## 7. Build passes

**All five passes are built** (2026-08). What the build changed from the
design above, in one place — the design text stays as written so the
deltas stay visible:

- **B4 was built before B3.** Two of the four watchers accept into coach
  tools; building the watchers first would have shipped suggestions whose
  accept button 404s. Order in the doc is by topic, not by dependency.
- **`Spending::Recurring` was extracted.** The design described
  new-recurring-charge and price-hike separately; they share one
  cadence-and-amount detector (≥3 charges, 24–38-day gaps, amounts steady
  within 5% allowing at most one price step), which is what lets a hiked
  charge report as a hike instead of also posing as a new subscription.
- **Refunds net inside their envelope** (Q-splits-and-refunds' first
  half, answered in code): a positive row filed to an expense category
  offsets that category's spending and floors at zero, rather than
  counting as income. Splits stay unbuilt.
- **Two DSL kinds joined `Tool::Base`**: `:budget_category` and
  `:ledger_month`, both own-data-only pickers.
- **`Suggestion` grew a `spending` action** — the one path from a mirror
  to the ledger, and still a click.

Original pass plan, for the record:

Each pass ends green (`bin/rails test`, `bin/rubocop`), registries updated
(`Tool::SLUGS`, watcher registry, routes, fixtures — the keep-both merge
files), and a `docs/status/` entry added. Passes are ordered by dependency;
B1/B2 are the meat, B3–B5 are each small.

- **B1 — the ledger.** `households.currency`; `spending_accounts` +
  `spending_rules` (primary); `spending_transactions` (mirror migration);
  statement import (Document → `Spending::StatementImport`: OFX/QFX parser +
  CSV with saved per-account mapping), dedupe + tombstones + transfer
  detection; manual quick-log; categorization pipeline (rules → keywords →
  validated model batch); `/spending` browse with recategorize-and-offer-rule;
  `spending.csv` in export. *Test spine*: parser fixtures across bank CSV
  shapes and OFX, import idempotency, transfer pairing, rule precedence,
  malformed model labels dropped.
- **B2 — the budget.** `budget_categories`; `Money::MonthSummary`;
  `Sections::Panels::Money` + `Sections::Panels::Budget` + partials;
  `build_my_budget` (both paths: from-history and intake), suggest-and-apply
  with the `target_set_by` guard. *Tests*: month math (boundaries, pace,
  unbudgeted), apply-never-overwrites-hand-set, WebMock tool runs.
- **B3 — staying faithful.** The four watchers (`budget_pace`,
  `new_recurring_charge`, `price_hike`, `month_close`), digest integration,
  panel invitation states. *Tests*: pure-SQL watcher signal tests
  (thresholds, fingerprints, no-signal-no-nudge), accept payloads.
- **B4 — the coach.** `money_coach` (chat: modes, context block, code-
  appended notice, recaps) + `spending_review` (aggregates-in, D28 routing
  out). *Tests*: chat lifecycle per the D29 spine, notice line asserted in
  code, next_tools sanitization, cut numbers traceable to input aggregates.
- **B5 — the wider money manager** (each on demand): `debt_payoff_plan`;
  email-receipt suggestions (the EMAIL_PLAN parked item — deterministic
  detection over the mail mirror, accept logs the transaction); comp-timeline
  hours-of-work garnish if it didn't fit in B4.

---

## 8. Decisions proposed (for DECISIONS.md)

- **D-spending-mirror.** Transactions are the second mirror source: statement
  files are vault Documents (the durable artifact) fanned into mirror rows;
  manual and receipt rows join them; dedupe by bank id else fingerprint,
  deletions tombstoned; transfers flagged and excluded from spending math.
  Two deliberate deviations from the email defaults, reasoned: **retention is
  keep-everything** (tiny rows; history is the value) and **the export
  includes `spending.csv`** (bank portals age out; the mirror becomes the
  only copy — email's mailbox-is-truth argument doesn't hold here).
- **D-budget-envelopes.** A budget is user-owned monthly envelope targets
  (`budget_categories`: Needs/Wants/Savings-&-debt groups + optional income)
  over the same categories the ledger files into; month math is a derived
  view (`Money::MonthSummary`), never stored; rollover deferred; budgets are
  per-user and private with no grants path. Categorization is
  **rules-before-model**: user rules from one-click feedback decide first,
  keywords second, batched validated model labels last, user hand-sets never
  overwritten. Budget drafting is suggest-and-apply through the D17 gate.
- **D-money-coach.** Money coaching is **support, not advice** (the D32
  boundary, translated): a chat tool with mode presets whose one hard
  guardrail is code — the not-a-financial-advisor notice — and whose prompt
  forbids specific investment/tax/credit-product recommendations and steers
  debt distress to nonprofit credit counseling and the app's own letter
  tools. The coach defends the user's own plan back to them, never shames,
  and helps fit the purchase in when the user overrules it. Faithfulness
  nudges are deterministic pace facts (per-envelope-per-month fingerprints),
  never spending commentary; no signal, no nudge.

### Open questions (slug-named, same collision logic as D-slugs)

- **Q-bank-connections.** Direct bank sync without a landlord: SimpleFIN
  Bridge, GoCardless-style PSD2 access (EU), FinTS/HBCI (DE) are candidate
  open-ish rails; any build follows the D27 shape (stateless, self-hostable,
  BYO escape hatch). Statement import must stay first-class regardless —
  it's the path that works for every bank on earth. — *Not started.*
- **Q-household-budget.** Joint budgets: shared envelopes, two ledgers, one
  plan. Real demand, real complexity (whose ledger feeds a shared envelope?);
  the mirror's structural privacy makes this genuinely hard, which is why v1
  is honestly per-user. Decide after real households ask. — *Not started.*
- **Q-splits-and-refunds.** Split transactions (one Costco run, three
  envelopes), refunds/reimbursements netting against spending. V1: whole-row
  categorization only; a refund is a positive row in the same category.
  Revisit when meters mislead in practice. — *Not started.*
- **Q-balances-and-assets.** OFX carries balances; net worth is the Assets
  subsection's future. Deliberately out of the budget buildout — flow first
  (the PRODUCT.md line), stock later. — *Not started.*
