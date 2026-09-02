# INTAKE_PLAN.md

Build plan for **document intake**: upload anything — a photo of the vet's
discharge sheet, a scanned lease, a PDF lab report, a pay stub — and the app
reads it, works out what in it belongs *somewhere else* (a visit on the
calendar, a new medication, the vet as a contact, a weight on the pet's
record, a bill in the ledger), and shows you the lot on one page to approve,
uncheck, and save. The file itself is always kept, whatever you decide.

The whole plan turns on one claim: **the list of things the model is told the
app can store, the code that validates its answer, and the code that writes
the rows must be one object, or they drift.** Today they are three objects in
three files, none of them shared, and it has already drifted (§1.2).

Decisions here are logged as **D-landing-registry** and **D-document-intake**.
Open questions are **Q-intake-stated-due** and **Q-intake-edit-in-review**.

**Status: designed 2026-09, not started.** §8 is the wave plan.

---

## 1. What we're building and why

### 1.1 The request, and the gap

The prompt was a photo of a vet report: "I want to log what all they did."
Today that photo uploads fine, files to Rex in one click from the pet page,
and then sits there — `Documents::Analyze` reads PDFs and text files only, so
the image lands in `analysis_status: failed` with "Text can't be extracted
from image/jpeg files yet." A PDF of the same report would get a summary
paragraph and a section suggestion, and nothing else: the visit doesn't reach
the care radar, the rabies booster's due date doesn't reach the calendar, the
prescription diet doesn't reach the food shelf, the vet doesn't reach the
Address Book, and the weight doesn't reach the pet. All of it is retyped by
hand, from a document the app is holding.

That is the general failure, not a pet one. A lease states a rent amount, a
due day, a landlord, and a move-out notice period. A lab report states a
result date and a follow-up. An insurance card states a plan, a member ID and
a phone number. A school letter states a deadline. The vault reads all of
these and understands none of them, and the target user — the one without an
assistant to hand a stack of paper to — is exactly the person a paper-to-rows
step is for.

### 1.2 Why the obvious fix is the wrong one

The obvious fix is the one already in the code: `PAY_STUB_FIELDS`, a
hand-whitelisted block for one document type, with one consumer
(`Career::PayStub`). Add `VET_VISIT_FIELDS`, then `LEASE_FIELDS`, then… Each
one is a new prompt paragraph, a new whitelist, a new writer, and a new
reason for the next primitive not to be covered.

Worse, the app already has **three** independent "the model proposed a row,
code writes it" paths, each with its own hand-written list of kinds:

| Where | Kinds it knows | Written by |
|---|---|---|
| `ToolRun#land_one` | note, task, event | a `case` statement |
| `Suggestion#materialize` | task, event, spending, agent_level, schedule_task | five `if` blocks |
| `Documents::Analyze#extracted_facts` | pay_stub | a constant + a method |

None of them shares a definition. When Notes grew `kind: "medication"` (D36)
and `kind: "allergy"` (D-allergy-notes), none of the three learned it; when
`PetFood` landed, none of them could propose one; the agent's prepared work
(D-agent-prepared-work) can stage a Note but not a Person. That is the drift
the request names — *"a big lift to keep that from drifting as we keep adding
more"* — and it is already here, in miniature, before intake exists. Intake
would be the fourth list. The plan is to make it the *only* one.

### 1.3 The claim

**A landing kind is one class** that declares, in one place: the fields the
model is told about (rendered into the prompt, never hand-written), the
validation of its answer into the closed set of things the app already has
(a `care_kind` from the registry, a pet from the household's pets, a date
that parses, a form from `PetFood::FORMS`), the write that turns the
validated attributes into a row, and the preview the review page shows before
that write. The prompt is *generated from* the registry, so a kind that isn't
registered cannot be proposed, and a registered kind cannot be proposed
without a writer. Every path that lands model-proposed rows — documents, the
agent's prepared drafts, and in time suggestions — resolves its kinds through
the same registry.

And the drift guard is a **test that enumerates what the app stores and
fails when something new isn't accounted for**: every primitive in
`Users::Export::MODELS` (the one list that already has to know everything the
user owns, because it has to give it back) is either covered by a landing
kind or named on an explicit not-intake list with a reason. Adding a
primitive without deciding whether paper can produce it becomes a red test,
not a quiet omission.

---

## 2. The decisions

### D-landing-registry. One registry of landing kinds is what the model is told, what code validates against, what writes the row, and what the review page renders.

`app/landings/landing.rb` is the registry (`Landing::KINDS`, `Landing.find`),
on the pattern `Tool::SLUGS` and `Watcher::SLUGS` already use; kinds live in
`app/landings/landing/<kind>.rb` and inherit `Landing::Base`. A kind
declares:

```ruby
class Landing::Event < Landing::Base
  self.description = "an appointment, visit, deadline or renewal date the document states"
  field :title,       "short; names whom it is about (\"Rex — vaccinations\")", required: true
  field :on,          "YYYY-MM-DD", type: :date, required: true
  field :time,        "HH:MM, only when stated", type: :time
  field :location
  field :description, "anything else the document says about it"
  field :care_kind,   "which routine care this was, if any", type: :choice, choices: ->(ctx) { ctx.care_kind_keys }
  field :pet,         "the pet it is about, if any", type: :ref, ref: :pet

  def land!(user, attrs, filing:) … end      # → an Event, tagged
  def preview(attrs) … end                   # → title / detail / chip for the review page
  def fingerprint(attrs) … end               # → "event:2026-08-12:rex-vaccinations"
end
```

Four things fall out of the declaration, and none of them is written twice:

- **The prompt block.** `Landing.prompt_block(context)` renders every kind as
  one paragraph — its description, its fields, and for `:choice` and `:ref`
  fields the closed list the answer must come from. The listing of pets,
  people, care kinds and sections that references resolve against is
  rendered once, by code, from what the requesting user can see.
- **Validation.** `Landing::Base#validate(raw, context)` walks the declared
  fields: unknown keys dropped (the `PAY_STUB_FIELDS` discipline, generalized),
  dates parsed or dropped, choices matched against the closed set or dropped,
  refs resolved through `visible_to` or dropped, required fields missing →
  the whole landing is dropped. The model's output is never trusted past this
  method, and every kind gets the same treatment for free.
- **The write.** `land!` is the only place that knows the row. The
  `ToolRun#land_one` case statement becomes `Landing.find(kind).land!(…)`, so
  the agent's prepared work can stage any registered kind the day the kind
  exists.
- **The preview.** `preview` gives the review page and `_prepared.html.erb`
  the same `Landing` value object `ToolRun#landings` already builds by hand.

**What a kind is not.** Not a new primitive, not a table, not a form: a kind
is *how paper becomes a row that already has a model*. `Landing::Medication`
writes a `Note` with `kind: "medication"` exactly as the Medications card's
form does; `Landing::PetFacts` updates columns on a `Pet`. The primitives
stay the six-plus-the-rest the architecture already has.

**Updates as well as creates.** A vet report states a weight and a microchip
number; those belong on the `Pet` row, not in a new one. A kind may be an
*amendment* — `land!` updates an existing record the ref resolves to — and its
preview shows old → new ("Weight: 31.2 kg → 32.6 kg"). The D16 hand-set guard
holds: an amendment never overwrites a value the user typed unless they tick
it, and the preview says which values it would replace.

**The drift guard, in tests:**

1. Eager-load; every `Landing::Base` descendant is in `Landing::KINDS`
   (the `vault_sealed_test.rb` shape).
2. Every `Users::Export::MODELS` key is either produced by some kind's
   `produces` declaration or listed in `Landing::NOT_INTAKE` with a reason.
   The initial not-intake list is honest about why: `photos` (a photo of a
   photo is a photo — upload it there), `albums`, `credentials` (a password on
   paper goes through the vault's own form and never through a model),
   `feeds`, `suggestions`, `recipes` (has its own paste-import with a
   deterministic parser — RECIPES_PLAN §5.1 — which intake should *route to*,
   not duplicate), `spending_accounts`, `budget_categories`, `spending_rules`,
   `recipe_books`.
3. Per-kind round-trip: a fixture answer in the model's shape validates to the
   expected attributes, drops the planted garbage, and `land!` produces the
   expected row. One test file per kind, next to it.

### D-document-intake. A document proposes; the review page disposes. The file is always kept; nothing else lands without the click.

The document is the run. Analysis writes what it found into
`documents.landings` (JSON, one entry per proposed landing: kind, validated
attributes, fingerprint, status `proposed`), and the review page at
`/documents/:id/review` shows them as a checklist — every entry checked, the
preview from its kind, the filing it would get — with one Save. Saving calls
each checked kind's `land!` inside a transaction, records provenance in
`document_items` (the `tool_run_items` shape: which rows this document
produced), and marks the entry `saved` with the item's type and id.
Unchecked entries are marked `skipped`, not deleted: they stay on the
document, the page shows "3 things you skipped" with a way back, and a
re-analysis never re-proposes a fingerprint that is already saved or skipped.

Three rules the page's copy has to make true:

- **Nothing on the page exists yet.** The `_prepared.html.erb` line —
  "Nothing is saved yet — read it, then decide" — is the same line here, for
  the same reason. The D16 exceptions are the ones that already exist and no
  more: an untagged document still gets its section suggestions applied, and a
  document whose title is still the cleaned-up filename ("IMG 4032") takes
  the model's title. Both are filing, both are overwritable, neither is a row.
- **The file is always kept.** The document row exists from the upload; the
  review is over what it *implies*, and skipping all of it is a complete,
  respectable outcome. A photo of a receipt you only wanted in the vault is
  not a failed intake.
- **The document's filing is the landing's default filing.** A landing
  inherits the document's sections — upload from Rex's page and every event,
  note and medication it produces is tagged Rex — plus whatever the kind adds
  (a vet visit is Health). This is inheritance, not classification: no model
  call decides where the landing goes beyond the taxonomy suggestion it
  already makes for the document itself.

**Pay-stub facts stay facts.** `extracted_facts["pay_stub"]` is a record of
what *this document says*, consumed by `Career::PayStub` against the document
itself, not a row elsewhere; it moves into the registry as a fact-shaped kind
(so its fields are declared once and validated the same way) but its storage
and `Career::RecordCompChange`'s automatic comp-change event are unchanged —
D-career-signal decided that rung, and intake doesn't reopen it. The
distinction is worth keeping for the next case too: **facts** live on the
document, **landings** become rows elsewhere and wait for the click.

**Images go through the vision path the app already has.** `Photos::Caption`
sends a resized data URL to the household's vision-declared model;
`Documents::Analyze` gains the same rung for `image/*` files, and for PDFs
whose pages carry no text (a scan) — rendered to an image through the vips
loader, first pages only, capped. With no vision model declared the document
says so — "This model can't read images. Turn on vision in Settings if it
can, or upload a PDF" — and does not guess (D-no-keyword-logic's no-model
rule). Text and text-bearing PDFs keep the cheap path they have.

---

## 3. What the model is told

One call per document, in the shape every classifier in the app already
uses (`Notes::Categorize`, `Feeds::Classify`, `Email::Triage`): a system
prompt that says what the feature is and the rules, a user prompt that
carries the document and the closed lists, JSON back, validated.

The system prompt is assembled by code from four blocks:

1. **What this is.** The document-understanding feature of a private,
   self-hosted assistant; summary in plain language (unchanged from today).
2. **What the household stores** — `Landing.prompt_block`, the generated
   paragraph per kind. This is the block that answers "have the AI know what
   all we store": it is never hand-written, so it can't fall behind the code.
3. **The rules**, authored once for every kind: emit a landing only for what
   the document *plainly states*; copy numbers, dates and names as printed;
   omit any field the document doesn't give rather than guessing; one landing
   per fact; a past visit is an event in the past, a stated due date is an
   event in the future; at most `MAX_LANDINGS` (12 to start).
4. **The closed lists** the refs resolve against, rendered from the
   requesting user's view: the section taxonomy (`Llm::Taxonomy.listing`),
   the household's pets with species and breed (the `Photos::Caption`
   listing), the people the user can see (name and relationship, capped), and
   the care-kind keys — the user's from `Health::CareRadar::KINDS`, each pet's
   from `Pets::CareKinds.for(pet)`.

The user prompt carries the document: title, description, the sections it
is already filed under ("Filed about: Rex — dog, golden retriever"), and the
text or the image. The response is
`{"summary", "sections", "title", "landings": [{"kind", …fields}], "facts": {…}}`.

**Keeping it affordable (the Tier-A constraint).** The block grows with the
registry, and small local models have small windows. The escape hatch is the
one D-no-keyword-logic sanctions — *ask about less*, never swap the mechanism:
when `Landing.prompt_block` exceeds `SCHEMA_BUDGET`, the call splits into a
**presence pass** (summary, sections, and *which kinds this document
contains*, from the list of kind names) and a **detail pass** carrying only
the present kinds' fields. Designed now, built when the block crosses the
budget (§8, W5); v1 is one call.

---

## 4. The kinds

The registry's first residents, in the order the waves land them. Each is a
short class; the table is the whole spec.

| Kind | Writes | Fields (refs and choices in *italics*) | Notes |
|---|---|---|---|
| `event` | `Event` | title, on, time, location, description, *care_kind*, *pet* | The workhorse: visits, deadlines, renewals, due dates. A past visit with a care kind is what makes the care radar count it. |
| `task` | `Task` | title, due_on, notes | "Bring a stool sample to the next visit." Lands in Later/Today by date, as `Tool::Base#create_task` does. |
| `note` | `Note` (plain) | title, body | The catch-all for a fact worth keeping that has no shape: "Dr. Alvarez says the limp is arthritis, not the cruciate." |
| `person` | `Person` | name, relationship, phone, email, address | The vet, the landlord, the specialist. Matched against visible people by the model's *ref* first — an existing person is an amendment, not a duplicate. |
| `medication` | `Note` (`kind: medication`) + optional refill `Event` (`care_kind: none`) | name, dose_and_schedule, refill_on, *pet* | Exactly what the Medications card's form writes (HEALTH.md §7). |
| `allergy` | `Note` (`kind: allergy`) | allergen, reaction, *severity*, *pet* | Severity from `Note::SEVERITIES` or omitted — never guessed (HEALTH.md §8). |
| `pet_facts` | amends `Pet` | *pet*, weight_kg, microchip, born_on (+ estimated), *vet* | The amendment kind. Preview shows old → new. |
| `pet_food` | `PetFood` | *pet*, name, brand, *form*, amount_per_day + *unit*, package_amount + *unit*, package_cost, started_on | The prescription diet on the discharge sheet. Numbers copied as printed; the shelf's own validation applies. |
| `spending` | `SpendingTransaction` on the Cash account | amount, occurred_on, merchant, descriptor | The vet bill, the receipt. Same path `Suggestion#materialize`'s `spending` key takes, moved here. Never lands twice: fingerprint on amount + date + merchant. |
| `health_plan` | sets `documents.health_plan` | — | The document *is* a policy. This replaces the `Health::Coverage` keyword heuristic for analyzed documents — the D-no-keyword-logic cleanup that falls out for free. |
| `pay_stub` | facts on the document | the existing `PAY_STUB_FIELDS` | Unchanged behavior, declared once. |

What a vet discharge sheet produces, concretely: an `event` on the visit
date with `care_kind: pet_vaccinations` (the radar's "last visit" for that
kind moves), an `event` in the future titled "Rex — rabies booster due" with
`care_kind: none` (so the calendar and renewal radar give lead time without
the care radar reading a due date as a booking — Q-intake-stated-due is
whether it should), a `medication`, a `pet_food` if the diet changed, a
`pet_facts` amendment for the weight, a `person` for the vet if she isn't in
the Address Book — with the `pets.vet_id` amendment riding along — and a
`spending` for the bill. Everything the request asked for, each row where
its own page expects it, and one page to say yes to.

---

## 5. The review page

`/documents/:id/review`, reached from the document page's banner the moment
analysis finishes with landings ("We found 6 things worth saving — review
them") and linked from the pet page's Papers card while any are still
proposed.

Anatomy, top to bottom:

1. **The document** — the image or first page, its summary, and its filing.
   This is the page's evidence: every card below should be checkable against
   what is visibly on the paper.
2. **The landings**, one card per entry, grouped by kind in registry order,
   each with its checkbox (on), the kind's preview (title, detail, a chip:
   "calendar · 12 Aug 2026", "medication", "amends Rex"), and the sections it
   would be filed under. Amendments show old → new. A landing the
   deterministic duplicate check flags (same kind, same fingerprint, already
   a row this user can see — the same date and care kind on the same pet)
   renders **unchecked** with the reason and a link to the existing row.
3. **Save** and **Skip all**, with the `_prepared` copy: nothing is saved
   until you say so; skipping leaves the file exactly where it is.

What it deliberately isn't, in v1: an editor. A wrong date is fixed in the
row's own edit form after saving, where every field is (the D16 rule for
mis-filed items). Inline editing before the click is Q-intake-edit-in-review
and waits for real use to say which field is wrong often enough to earn it.

On mobile the cards are the page; the checkbox is the row's tap target, and
Save sits in the sticky bar the chat shell already uses (CHAT_PLAN's
screen/panel split).

---

## 6. The honesty line

- **The model reads; it does not decide what is true.** Every date, number
  and name lands as printed, validated for *shape* only. A document that
  says the wrong thing produces a landing that says the wrong thing, on a
  page whose whole job is to be checked against the paper. The failure to
  avoid is the confident silent write, and the click is what prevents it.
- **No landing is ever a diagnosis or advice.** A lab report produces a
  results-date event and, at most, a note quoting what the report says —
  never an interpretation. `results_explainer` is the tool for that, and the
  review page can route to it (D28's `next_tools`, on a document instead of a
  run).
- **Refs never resolve by name-matching in code.** "Dr. Alvarez" becomes a
  link to the existing Person only if the model chose her from the listing
  it was shown; the Q8/Q17 rule — name-matching may suggest, never assume —
  is the model's suggestion validated against the closed list, and a miss is
  a new-person landing the user can uncheck.
- **Provenance is named.** A row that came from a document says so on its
  page ("From the vet report of 12 Aug — edit or delete this if it isn't
  right; your word beats the reader's"), through `document_items`, the same
  sentence `Career::RecordCompChange` already writes.

---

## 7. Sharing and privacy

Nothing new. The document is read through its owner's model profile, as it is
today; the closed lists in the prompt are rendered from `visible_to(owner)`,
so a household member's unshared people and pets never appear in the listing
and can't be referenced. Rows a document produces belong to the document's
owner and follow the normal sharing rules from their own pages. Deleting a
document deletes its `document_items` join rows and nothing else — the visit
happened whether or not you keep the scan.

---

## 8. Waves

**W1 — Read the image.** `Documents::Analyze#extract_text` becomes
`Documents::Read` with four rungs — text, text-bearing PDF, image (resized
data URL through the vision client), scanned PDF (page renders, capped) — and
the honest no-vision message. The document page shows the image. No registry
yet; the vet photo now gets the summary and the section suggestion a PDF
gets today. Smallest wave, general value (receipts, letters, lab results),
independent of everything below.

**W2 — The registry, and the kinds that already have writers.**
`Landing` + `Landing::Base` + the field DSL; `event`, `task`, `note`,
`person`, and the document's own `title`; `documents.landings` and
`document_items`; `Landing.prompt_block` in the analyze prompt; the review
page; the duplicate flag; the drift-guard tests with the not-intake list.
`ToolRun#land_one` moves onto the registry in the same wave — it's a
seven-line change and the proof that the seam is shared. `pay_stub` moves in
as the fact-shaped kind so `PAY_STUB_FIELDS` has one home.

**W3 — The health and pet kinds.** `medication`, `allergy`, `pet_facts`
(the amendment machinery, with old → new previews), `pet_food`, the
`care_kind` choice on `event`, and the pet and person refs with their
listings. This is the wave that lands the vet report. Add the "from this
document" line to the rows' pages.

**W4 — Money and coverage.** `spending` (moved from `Suggestion#materialize`,
which then calls the registry for it), `health_plan` (retiring the keyword
match in `Health::Coverage` for analyzed documents — the pin column keeps
its meaning as the owner's override). Route lease- and bill-shaped documents
to `decode_letter` through a document-side `next_tools`.

**W5 — Guards and growth.** The presence/detail split when
`Landing.prompt_block` crosses `SCHEMA_BUDGET`; the skipped-landings revisit
strip; `Suggestion#materialize`'s remaining keys onto the registry where they
are creates (task, event) — `agent_level` and `schedule_task` are not
landings and stay where they are.

Each wave lands green and is useful alone. W1 by itself turns the photo into
a searchable summary filed under Rex; W1+W2 makes any document produce
calendar entries and contacts; W3 is the request.

---

## 9. Deliberately not built

- **Multi-photo documents.** Three photos of a three-page report are three
  documents in v1, each read alone. A "pages" join on Document is a real
  later rung (the vault would want it for any scanned bundle) and waits for
  the single-page version to prove the page.
- **Editing in the review** (Q-intake-edit-in-review).
- **A stated due date beating the registry interval on the care radar**
  (Q-intake-stated-due). The vet's "next rabies 2029" is better information
  than "12 months from the last one", and the radar can't yet hold it.
- **Recipes through intake.** A photo of a recipe card is a real want and
  `Recipes::Import` is the right reader for it — its deterministic ingredient
  parser is the reason it exists. Intake should *recognize* a recipe and route
  to that importer with the extracted text (the presence pass makes this a
  one-line kind), not re-implement it.
- **Anything that reads the document for the user's benefit and writes for
  someone else's.** Intake writes only the uploading user's rows; a shared
  document read by a household member proposes into *their* space, over
  *their* visible lists.
- **Auto-save for "confident" landings.** The trust ladder's rung above the
  click is Q19's outbound-consent design, and it should wait for prepared
  work to run in real houses (STATUS.md's parked tail) before intake asks to
  skip a click on the user's own records.

---

## 10. Files (planned)

| Concern | File |
|---|---|
| Registry | `app/landings/landing.rb` (`KINDS`, `NOT_INTAKE`, `find`, `prompt_block`) |
| Base + DSL | `app/landings/landing/base.rb` (`field`, `validate`, `preview`, `fingerprint`, `land!`) |
| Kinds | `app/landings/landing/{event,task,note,person,medication,allergy,pet_facts,pet_food,spending,health_plan,pay_stub}.rb` |
| Ref listings | `app/landings/landing/context.rb` (taxonomy, pets, people, care kinds — rendered through `visible_to`) |
| Reading files | `app/services/documents/read.rb` (text / PDF / image / scanned PDF) |
| Analysis | `app/services/documents/analyze.rb` (prompt assembly from the registry; validation into `documents.landings`) |
| Saving | `app/services/documents/land.rb` (checked entries → `land!` in one transaction → `document_items`) |
| Schema | `db/migrate/*_add_landings_to_documents.rb`, `*_create_document_items.rb` |
| Review page | `DocumentsController#review`/`#land`, `app/views/documents/review.html.erb`, `app/views/landings/_<kind>.html.erb` previews |
| Shared seams touched | `ToolRun#land_one` (W2), `Suggestion#materialize` (W4/W5), `Health::Coverage.match?` (W4) |
| Tests | `test/landings/registry_test.rb` (the drift guard), `test/landings/<kind>_test.rb`, `test/jobs/analyze_document_job_test.rb`, `test/controllers/documents_controller_test.rb` |
| Registries touched | `Users::Export::MODELS` (nothing new to export — `document_items` is provenance, not owned data; the drift test *reads* this list) |

**Adding a primitive later?** Write its `Landing::<Kind>` or add it to
`Landing::NOT_INTAKE` with a reason. The registry test fails until you do
one or the other; that is the whole anti-drift mechanism, and it is
deliberately a test rather than a convention.
