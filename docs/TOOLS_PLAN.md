# TOOLS_PLAN.md

Build plan for the **high-impact tool wave**: the seven tools chosen (2026-08) as the
biggest-leverage things the app can do for the 99%, plus the three infrastructure seams
they need. This expands ROADMAP.md §2's "first tool slate" — items already built there
(dispute letter, learn something) are the foundations this wave rides on; items still
parked there (cancel-subscription, reconnect, Situations) are unaffected and slot in
after or between waves.

Proposed decisions here are logged as **D21–D22** in `DECISIONS.md` (provisional until
their build passes prove them, same convention as D18–D20).

---

## 1. What we're building and why

Ranking calculus: **stakes × frequency × counterfactual (does the user have *any*
alternative?) × Tier-A feasibility**. The structural insight behind the slate: most
money the 99% lose is lost through **inaction at deadlines** — unappealed denials,
unanswered collection suits, unclaimed benefits, unsent demand letters. Every tool
below ends in a draft the user can send plus the deadlines as owned Events/Tasks.

| # | Tool | Section(s) | Kind | Why it's top-tier |
|---|---|---|---|---|
| 1 | **Decode this letter** | rights, money, health (+ vault entry) | draft | Universal triage for scary mail; the *front door* that routes to every other tool at the moment of crisis. |
| 2 | **Benefits & credits screener** | benefits | draft | Tens of billions unclaimed yearly because people don't know they qualify; highest dollars-per-engineering-hour in the app. |
| 3 | **Appeal/response family** — insurance appeal, debt-collector response, deposit demand | disputes (+ health / debt / renting) | draft | <1% of denials are appealed though appeals often succeed; most collection suits end in default. Specialized letters with the statutory deadlines built in. |
| 4 | **Negotiation prep** | career, renting, bills | draft | The wealthy negotiate through agents; most people accept the first number. Salary outcomes compound for decades. |
| 5 | **Doctor-visit prep** | health | draft | Already on the M2.3 slate; the visit is short, the history is long — arrive with the summary and the questions. |
| 6 | **Results explainer** | health | draft | Test results and diagnosis letters in plain language — *comprehension, not diagnosis* (carefully scoped per PRODUCT.md). |
| 7 | **Tutor** | education | **chat** (new kind) | Infinite patient 1:1 tutoring for user and kids; the differentiator is continuity with the owned memory (it knows your Learn-something plans). |

Nine tool classes total (the family is three), plus the existing `dispute_letter` as
the generic fallback the family specializes.

---

## 2. The three infrastructure seams

The existing infra (`Tool::Base`, `tool_runs` + `ToolRunJob`, Act-zone cards, the
shared `Goals::BreakDown`) carries most of this. Three seams need building, each
introduced by the first wave that needs it — never speculatively.

### S1. Shared draft plumbing in `Tool::Base` (wave 1)

`DisputeLetter` grew private helpers every document tool needs. Extract into
`Tool::Base` (or a small `Tool::DraftHelpers` mixin) so each new tool is *only* its
prompt and its landing logic:

- **`document(input_name = :document_id)`** — `Document.visible_to(user)` lookup +
  friendly `Llm::Error`s for missing doc / no extracted text, and the
  `MAX_DOCUMENT_CHARS` truncation. (Lifted verbatim from `DisputeLetter`.)
- **`file_under(items, *section_sets)`** — the "tool's sections ∪ source item's
  sections" filing rule, today private to `DisputeLetter#filing`.
- **`create_note(title:, body:)` / `create_task(title:, due_on:, notes: nil)` /
  `create_event(title:, date:, description: nil)`** — record + create in one, with the
  existing today/later bucket rule for tasks. **Events are new**: tools can now land
  deadlines as all-day Events (`all_day: true`, `starts_at` at the date) so they hit
  Calendar/Today like everything else. Statutory deadlines are the whole point of the
  letter family; a Task can be snoozed, a calendar Event is harder to lose.
- **`section_context(slugs, budget:)`** — gather owned context beyond one document: the
  user's `visible_to`-scoped Notes / Events / Documents / Tasks tagged with the given
  sections, rendered as a compact text block under a character budget (newest first,
  truncate per item, stop at budget). Needed by doctor-visit prep (wave 2) and the
  tutor (wave 5); built in wave 1 only as far as wave 2 needs it.

### S2. Tool routing — `next_tools` (wave 3, **D21**)

Decode-this-letter's whole value is *routing*: it must end with "this is an insurance
denial — draft the appeal?" and one click must open that tool with the document already
selected. Mechanism:

- A tool's `handle` may write **`run.output["next_tools"]`**: an array of
  `{ "slug": ..., "inputs": {...}, "reason": ... }`. Slugs are validated against
  `Tool::SLUGS` and inputs against the target tool's declared input names before
  storing — the model proposes, the code sanitizes.
- The run show page renders these as **next-step cards** linking to
  `new_tool_run_path(tool_slug, inputs: {...})` — the controller *already* accepts
  prefilled inputs (that's how "Run again" works), so prefill costs nothing new.
- **Document-page entry point**: a document's show page (and vault rows) gets a
  "What is this / what do I do?" button → decode-letter prefilled with that document.
  This is the pull-mode version; auto-suggesting decode after `AnalyzeDocumentJob` is
  agent-era (a watcher + suggestion, M3) and explicitly out of scope here.

Routing is data in `output`, not behavior: no tool ever *runs* another tool. The user
clicks through a prefilled form and the normal run lifecycle applies. (Trust-ladder
discipline, same as D19/D20.)

### S3. Chat tools — a third kind (wave 5, **D22**)

Tutoring is a conversation, not a one-shot pipeline. Rather than bolt a separate chat
feature onto the app, chat becomes the third tool kind, reusing the entire run
lifecycle (Act-zone card → run page → history):

- **`kind: :chat`**. New table **`tool_run_messages`**: `tool_run_id`, `role`
  (`user`/`assistant`), `content` (text), timestamps. The run's `inputs` still capture
  the opening form ("What are we working on?").
- **Lifecycle**: `ToolRunJob` generates the *opening* assistant message from the
  tool's system prompt + owned context, then marks the run `done` — for a chat tool,
  `done` means "live", not "finished"; the composer stays available on the run page.
  Each user message → `ToolRunMessagesController#create` → `Tool::ChatTurnJob` →
  append the assistant reply, Turbo-Stream it in. A turn that fails appends a
  retryable error bubble; it never poisons the run.
- **Context window discipline**: send the system prompt + the last `N` messages
  (start at 30); older turns drop off. Model-agnostic constraint: this must work on
  small local models, so the prompt stays lean.
- **Landing primitives**: a "Save a recap" action on the run page makes one wrap-up
  LLM call → a Note ("What we covered — <topic>", filed under the tool's sections)
  recorded on the run via the normal `tool_run_items`. The transcript itself is the
  run's; the *recap* is the owned primitive. No auto-writes (D20 discipline).
- Chat runs are private to their user like all runs; recaps follow normal sharing.

This seam is deliberately last: it's the largest and nothing else depends on it.

### Minor DSL growth (wave 4)

The benefits screener needs structured intake. `Tool::Base::Input` gains two kinds:
**`:select`** (with an `options:` list) and **`:checkboxes`** (multi-select, stored as
an array in `inputs`). The generic tool form renders them; `ToolRunsController`'s
strong params learn to permit array values for checkbox inputs. No other tool needs
them yet; built when needed.

---

## 3. Wave plan

Each wave is one focused build pass: migrations (if any) + tool classes + tests +
Act-zone verification, ending green (`bin/rails test`, `bin/rubocop`) and with
CLAUDE.md's "where we left off" updated. Order is by infrastructure dependency, not
importance — the front-door tool (decode) needs its routing *targets* to exist first.

### Wave 1 — shared plumbing + the single-document drafts (M2.3a)

Extract S1 from `DisputeLetter` (behavior-neutral refactor, existing tests stay
green), add the Event helper, then four new tools that are each ~a prompt:

1. **`results_explainer`** (Health) — the simplest possible new tool; proves the
   extracted helpers.
2. **`insurance_appeal`** (Disputes + Health)
3. **`debt_collector_response`** (Disputes + Debt)
4. **`deposit_demand`** (Disputes + Renting)

### Wave 2 — owned-context drafts (M2.3b)

Build `section_context` (S1's last piece), then:

5. **`doctor_visit_prep`** (Health) — first tool that reads a *section*, not a document.
6. **`negotiation_prep`** (Career + Renting + Bills) — free-text context + optional
   document; exercises the optional-document path.

### Wave 3 — the front door (M2.3c, D21)

`next_tools` routing + document-page entry point, then:

7. **`decode_letter`** (Rights + Money + Health + vault) — routes to everything built
   in waves 1–2 plus the existing `dispute_letter`.

### Wave 4 — the money-on-the-table tool (M2.3d)

`:select`/`:checkboxes` input kinds, then:

8. **`benefits_screener`** (Money → Benefits).

### Wave 5 — the tutor (M2.5, D22)

`tool_run_messages` + chat lifecycle + run-page chat UI, then:

9. **`tutor`** (Education).

Numbering note: ROADMAP's M2.4 (Situations, "moving" first) is untouched and can be
built before, between, or after waves 3–5 — it shares no seams with this plan beyond
what M2.2 already proved.

---

## 4. Per-tool specs

Shared conventions (all tools): Tier A only — owned data, no web capability assumed;
all output is draft output, nothing is ever sent; context reads go through
`visible_to(user)`; letters use `[BRACKETED PLACEHOLDERS]` for unknown details, never
invented facts; created primitives are filed under the tool's sections ∪ the source
item's sections (the `DisputeLetter` rule); JSON response contracts follow the
established `{"letter": {...}, "follow_ups": [...]}` family shape.

### 4.1 `results_explainer` — "Explain my results" (Health, draft)

- **Inputs**: `document_id` (required — lab results, imaging report, diagnosis
  letter, EOB); `question` (optional one line — "what does the cholesterol number mean?").
- **Context**: the document's extracted text.
- **Output contract**: `{"explanation": {"title", "body"}, "questions_for_doctor":
  ["...", ...], "follow_ups": [{"title", "due_on"}]}`. Body structure: what this
  document is → what each flagged value/term means in plain language → what's normal
  vs. outside range *as stated in the document itself* → what to ask the doctor.
- **Lands**: one Note (explanation, with the doctor-questions appended as a checklist
  section); ≤2 follow-up Tasks (e.g. "book the follow-up the report recommends").
- **Guardrails (the carefully-scoped part)**: system prompt hard-codes *comprehension,
  not diagnosis* — explain terminology and reference ranges, never infer new
  diagnoses, never recommend treatment changes, always defer interpretation to the
  clinician; the Note body ends with a fixed disclaimer line appended by *code*, not
  the model. No severity speculation on ambiguous values — "ask your doctor about X"
  is the ceiling.

### 4.2 `insurance_appeal` — "Appeal this denial" (Disputes + Health, draft)

- **Inputs**: `document_id` (required — the denial letter / EOB); `intent` (optional —
  "the ER visit was emergency care").
- **Output contract**: letter + follow-ups (family shape) **plus**
  `"deadlines": [{"title", "date"}]`.
- **Lands**: the appeal letter as a Note; follow-up Tasks; each deadline as an
  all-day **Event** (first tool to use the Event helper).
- **Prompt specialization**: identify plan type signals if present (employer plan vs.
  marketplace vs. Medicare Advantage — placeholder if unknown); structure as a formal
  internal appeal citing claim number, date of service, denial reason verbatim, and
  the requested outcome; request the specific plan documents (the denial's stated
  reason's evidence-of-coverage clause); state the intent to pursue **external review**
  if the internal appeal fails; extract the appeal-window deadline from the letter
  when stated, else a placeholder Event title ("Appeal deadline — check your denial
  letter, often 180 days").

### 4.3 `debt_collector_response` — "Answer a debt collector" (Disputes + Debt, draft)

- **Inputs**: `document_id` (required — the collection notice); `stance` (optional —
  "I don't recognize this debt" / "the amount is wrong" / "it's mine, I want to settle").
- **Output contract**: letter + follow-ups + deadlines (as 4.2).
- **Prompt specialization**: default posture is a **debt-validation request** (the
  FDCPA 30-day validation window is the single most valuable deadline in this
  domain — extract or flag it as an Event); demand validation in writing, dispute if
  stance says so, communicate-in-writing-only request; never admit the debt or promise
  payment unless the stance explicitly says settle; warn (in a code-appended note line)
  that a court **summons** is a different animal with a hard answer deadline — if the
  document looks like a summons rather than a collection letter, the letter is replaced
  by an urgent explainer: respond via the court, deadline as an Event, "answering
  prevents default judgment".

### 4.4 `deposit_demand` — "Get my deposit back" (Disputes + Renting, draft)

- **Inputs**: `document_id` (**optional** — the lease or the landlord's deduction
  letter, if in the vault); `details` (one line — "moved out June 30, $1,800 deposit,
  no walkthrough"). First family tool where the document is optional: the letter can
  be drafted from `details` alone with placeholders.
- **Output contract**: letter + follow-ups + deadlines.
- **Prompt specialization**: formal demand citing move-out date, amount, forwarding
  address line; requests the itemized deduction statement; notes that state law sets a
  return deadline and statutory penalties (jurisdiction as a placeholder — Tier A
  honesty: the model must not assert a specific state's day-count unless the user's
  data states the state, and even then phrase as "commonly/verify"); follow-ups include
  "send by certified mail" and a "no response by [date] → small claims" Task.

### 4.5 `negotiation_prep` — "Prep me to negotiate" (Career + Renting + Bills, draft)

- **Inputs**: `scenario` (`:select` is *not* needed — free text line, required:
  "salary offer from Acme", "rent renewal +$150", "internet bill"); `document_id`
  (optional — offer letter, renewal notice, bill); `constraints` (optional —
  "can't move before June", "target $85k").
- **Context**: the document if given, plus `section_context` for the tool's sections
  (a Career-tagged resume note or Bills-tagged history makes the prep concrete).
- **Output contract**: `{"prep": {"title", "body"}, "counter_message": {"title",
  "body"}, "follow_ups": [...]}`.
- **Lands**: a prep-sheet Note (their leverage, your leverage, opening position,
  walkaway point, likely objections + responses, phone script) and a *separate*
  counter-offer message Note (something send-ready to adapt); ≤2 Tasks.
- **Guardrail**: numbers the user didn't supply are placeholders — the model never
  invents market rates (Tier A: no web).

### 4.6 `doctor_visit_prep` — "Prep for a doctor visit" (Health, draft)

- **Inputs**: `reason` (required one line — "annual physical", "follow-up on the MRI,
  Dr. Chen"); no pickers (D16: the Health section context is read automatically).
- **Context**: `section_context(%w[health], budget: ~12k chars)` — recent
  Health-tagged notes (symptom journal entries), events (past visits), document
  summaries (prior results), open Health tasks.
- **Output contract**: `{"prep": {"title", "body"}, "questions": ["...", ...],
  "follow_ups": [...]}`.
- **Lands**: one Note — a one-page visit sheet: reason for visit, relevant history
  timeline (dated, from owned data only), current medications/symptoms *as recorded*,
  then the question list; optionally one Task ("bring the visit sheet + insurance card").
- **Guardrail**: history is strictly what's in the vault — the sheet says "based on
  what you've tracked here" and the model must not fill gaps with plausible history.

### 4.7 `decode_letter` — "What is this letter?" (Rights + Money + Health + vault, draft)

- **Inputs**: `document_id` (required); nothing else — the letter *is* the intent.
- **Entry points**: Act zones of Rights, Money, Health; a button on every document
  show page and vault row ("Decode this").
- **Output contract**:
  `{"decoded": {"title", "body"}, "deadlines": [{"title", "date"}],
    "next_tools": [{"slug", "inputs", "reason"}], "follow_ups": [...]}`.
- **Lands**: an explainer Note — what this document is, who it's from, what it's
  really saying, what happens if you do nothing, your options in plain language;
  every stated deadline as an all-day Event; ≤3 Tasks; and the **routing payload**
  (S2) rendered as next-step cards. The prompt gets the catalog of routable tools
  (slug + one-line description + inputs) and picks at most 2; code validates slugs
  and input names before storing.
- **Filing**: tool sections ∪ document sections — but the *decoded* note also inherits
  whatever section the model filed the document under, so a decoded EOB lands in
  Health even though decode is registered broadly.
- This is the tool that changes Rights' economics: six low-frequency tools stop
  needing discovery, because the letter itself offers them.

### 4.8 `benefits_screener` — "Am I leaving money on the table?" (Benefits, draft)

- **Inputs** (the one intake-form tool; all `:select`/`:checkboxes`/text):
  `state` (select), `household_size` (text), `monthly_income` (text, "roughly"),
  `circumstances` (checkboxes: kids under 18 · pregnant/new baby · 60 or older ·
  disability in household · veteran · recently lost a job · student · renter ·
  self-employed).
- **Context**: `section_context(%w[money benefits people])` as *supplementary* signal
  only — the form is the source of truth; owned data fills color ("you track 2 kids
  in People").
- **Output contract**: `{"report": {"title", "body"}, "programs":
  [{"name", "likelihood": "likely|maybe", "why", "how_to_apply", "first_step"}],
  "follow_ups": [...]}`.
- **Lands**: a screening-report Note (programs grouped **Likely** / **Worth
  checking**, each with why-you-match, what it's worth *in general terms*, and how to
  apply); one Task per *likely* program ("Start the SNAP application — <first_step>").
- **Guardrails (Tier A honesty — this is the tool most at risk of capability lies)**:
  the model screens from general program knowledge (SNAP, Medicaid/CHIP, EITC/CTC,
  WIC, LIHEAP, Lifeline/ACP-class programs, SSI/SSDI, unemployment, state variants it
  knows); every entry carries "rules change — verify at the official site" phrasing
  baked into the report template by *code*; no dollar-amount promises, only "often
  worth hundreds/thousands"; income thresholds phrased as "you're likely within range",
  never asserted as current law. The report footer states the screening date. When a
  `capabilities` flag lands (Q9), this is the first tool to upgrade to live rules.

### 4.9 `tutor` — "Study with a tutor" (Education, **chat**)

- **Inputs** (opening form): `topic` (required — "algebra homework", "Spanish
  practice", or pick up a Learn-something goal); `learner` (optional — "me" / "my
  9-year-old", shapes register and level).
- **Context** (system prompt): `section_context(%w[education])` — active
  Education-tagged Goals and their step Tasks (the Learn-something plans), recent
  recap Notes from *previous tutor runs*. This is the continuity moat: the tutor knows
  Tuesday's session struggled with fractions.
- **Behavior contract** (system prompt): infinitely patient 1:1 tutor; Socratic first
  (asks what the learner thinks before telling); adapts language and depth to the
  stated learner; for homework, guides to the answer rather than doing it; short
  turns — this is a dialogue, not lectures; plain text (small-model-friendly), no
  reliance on markdown tables/LaTeX.
- **Lifecycle**: opening message greets with where things stand ("Last time we covered
  X; your plan says today is Y — where do you want to start?"); "Save a recap" lands
  the wrap-up Note (what we covered, what clicked, what to practice) filed under
  Education and linked to the run; recap Notes are what future sessions read.
- **Explicitly not in v1**: auto-completing plan steps (suggest in the recap instead —
  D20: propose, don't dispose), voice, images/photo-of-homework (needs multimodal
  capability flags — Q9 territory).

---

## 5. Testing & conventions

Follow the established pattern (`test/jobs/tool_run_job_test.rb`,
`learn_something_tool_test.rb`): stub the OpenAI-compatible endpoint with WebMock,
run `ToolRunJob.perform_now`, assert on created primitives, filing, and run status;
provider-error and malformed-JSON paths fail the run with a friendly message.

Per-seam additions:
- **S1 refactor**: `DisputeLetter`'s existing tests must pass unchanged before any new
  tool lands — the extraction is behavior-neutral.
- **Routing (S2)**: unit tests that `next_tools` sanitization drops unknown slugs and
  undeclared input names; controller test that prefilled `inputs` params survive into
  the new-run form (already covered for "Run again" — extend).
- **Chat (S3)**: model/controller/job tests for the message lifecycle (user message →
  assistant reply appended; failed turn appends error, run stays live); recap test
  asserts the Note lands via `tool_run_items`.
- **Guardrail tests where code enforces them**: the results-explainer disclaimer line
  and benefits-report verify-footer are appended by code, so they're assertable
  without prompt-behavior tests.

Every wave ends with `bin/rails test` + `bin/rubocop` green, the new tools in
`Tool::SLUGS`, cards visible in their Act zones, and CLAUDE.md's "where we left off"
updated.

---

## 6. Decisions proposed (for DECISIONS.md)

- **D21. Tools compose by routing, not by calling each other.** A run's `output` may
  carry sanitized `next_tools` prefills rendered as next-step cards; decode-letter is
  the universal front door; documents get a decode entry point. No tool ever invokes
  another — the user always clicks through a prefilled form.
- **D22. Chat is a tool kind, not a separate feature.** `kind: :chat` +
  `tool_run_messages`; run page doubles as the chat surface; `done` = live; primitives
  land only via explicit "Save a recap". The tutor is the proving tool.

Open questions raised (candidates for the DECISIONS.md list):
- **Q11 — jurisdiction.** Deposit demand and benefits screener are state-sensitive.
  V1 handles it with placeholders + a form field; a household "state/country" setting
  would serve every Rights tool at once. Decide when a second tool needs it.
- **Q12 — chat transcript retention.** Tutor transcripts accumulate; recaps are the
  durable artifact. Prune old transcripts? Export them (D14's export leftover)?
  Decide before M3.
