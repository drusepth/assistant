# PETS_PLAN.md

Build plan for **pets**: the dog, the cat, the rabbit, the ageing horse — the
household members who can't log in, can't tell you what hurts, and cost about
what a car costs over a lifetime.

The whole plan turns on one claim: **a pet is a subject, not a section.** Vet
appointments are Health, kibble is Money, the photos are already in the
library, and "teach Rex to walk on a leash" is a Goal. Nothing about a pet
wants a new silo — what's missing is the ability to say *this item is about
Rex*, and one page where all of it converges.

Decisions here are logged as **D-pet-primitive**, **D-pet-care-radar**, and
**D-pet-food-shelf**. Open questions are **Q-pet-metrics** and
**Q-pet-sitter**.

**Status: built, W1–W5** (2026-08). §11 records what the build changed about
the plan — four things, all of them found by writing the code.

---

## 1. What we're building and why

Two thirds of households have a pet, and for the target user the pet is not a
hobby — it's a dependent with a medical history, a monthly cost, a prescription
diet, a rabies certificate the boarding kennel wants a copy of, and a rhythm of
care nobody is tracking. The paid version of this service is a vet practice's
app that knows only what that practice billed you for, plus a pet-insurance
portal, plus a bag of receipts. The pet's actual record — what she eats, what
she reacted to, when the limp started, which vet said what — lives in the
owner's head and evaporates at exactly the moment it's needed, which is
standing in an emergency clinic at 11pm being asked "and what's she on?"

Every piece of this is Tier A (owned data, any model), high-frequency, and
already half-built here:

- the **care radar** already answers "when was the last one, is one booked?"
  for a rhythm of routine appointments — a wellness exam is a checkup with a
  different noun;
- the **vault** already reads documents — a vaccination record is a document;
- the **budget** already tracks envelopes and recurring charges — food is the
  single most predictable recurring cost in the house;
- **photos** already exist, and the most photographed member of most
  households is the dog.

What's missing is small: a record for the pet, a way to say an item is about
her, and the page that gathers it.

The scope line is inherited from Health §1 and tightened: **preparation and
comprehension, never diagnosis.** It matters more here, not less. A person
with a worrying symptom can describe it; a dog can't, the owner is guessing
from behaviour, and the cost of a confident wrong answer is an animal that
didn't go to the vet. §6 makes that a code-authored guardrail rather than a
prompt's good intentions.

---

## 2. The decisions

### D-pet-primitive. A pet is a member of the household, and each pet owns a section lens.

Two halves.

**A `Pet` record**, because a pet has attributes nothing else can hold: species,
breed, sex (a closed set, because the app's own copy reads it to pick a
pronoun — D-pronouns), whether they're spayed or neutered, date of birth
(usually estimated), adoption date, colour and
markings, microchip number, an avatar, and the vet. It joins the shared pool on
the D5 contract — `belongs_to :user`, `include Visible`, `include Sectionable`,
`include Avatarable` — so sharing, tagging, and the face machinery all apply
without a new mechanism.

*Not a Person with a species column.* Person is a **contact**: email, phone,
`keep_in_touch`, `last_contacted_on`, the Address Book, the stay-in-touch
watcher. A pet filed there sits between your dentist and your landlord, and one
week later the app suggests you reconnect with the cat. That's a joke the app
gets to tell exactly once.

**And a lens per pet** — a `custom: true` child section under People, created
with the pet through the existing `Sections::Lens.find_or_create!("people", …,
fallback_slug: "pet")`. This is the load-bearing half. Because "about Rex" is a
*tag*:

- every form that already has a section picker can already file to Rex — no new
  link UI on six forms, which was half of what Q17 was waiting to pay for;
- `in_section(rex)` is "everything about Rex" across every primitive at once,
  including Photos, which are `Sectionable` too — so "show me pictures of my
  dog" is a query we already have rather than a `photo_pets` table;
- **per-pet sharing is a section grant** — "share all my Rex items with my
  husband" is the existing sentence, and household pets become the most
  natural section grant in the app;
- calendar filters, the browse page, the LLM's taxonomy listing, and agent
  dials all follow for free.

Pets therefore **do not force Q17** (person↔item links) and it stays deferred.
A lens answers "which pet" for the same reason a lens answers "which hobby":
the relationship is one-to-many and coarse. Q17's real consumer is still
attendees — many people per event, per-person history — and pets don't
demonstrate that need.

**Why not an eighth section.** It's the cheap answer and it's wrong, in a way
worth writing down because it's the failure the whole request is about.
Sections are the *what* axis — which area of life this belongs to. A pet is a
*whom*. File the vet appointment under a top-level "Pets" section and it stops
being Health: it drops off the care radar, out of the Health page, out of the
insurance card's reach; file the food under Pets and it leaves the budget.
Every surface that already works would have to be rebuilt inside the silo —
which is precisely what "standalone" means and precisely what we're avoiding.
As a lens, the vet appointment is `Health + Rex` and both pages are right.

Three smaller calls that follow:

- **Panel resolution grows one rung.** Custom sections under People currently
  all resolve to `Panels::PeopleLens` (a group's members page), which would show
  Rex's lens as a group whose members are the vet and the dog walker.
  `Sections::Panel.panel_class` gains a model-backed rung — a section a `Pet`
  claims resolves to `Panels::PetLens` — the same shape as the parent-lens
  fallback D37 already carries, generalized once. It is a shared file (D37's
  three), so it lands as its own small commit.
- **Renaming a pet renames the lens, not its slug.** Slugs are a global
  namespace feeding URLs and the LLM listing; rewriting one breaks bookmarks
  for a cosmetic gain. `available_slug` already numbers collisions, so two
  households' two Lunas are `luna` and `luna-2`.
- **Pets die, and the app must handle it well.** `died_on` (and `left_on` for
  rehomed) stops every radar, watcher and reorder, keeps the record, the
  photos, and the whole history, and moves the card to a quiet **Remembered**
  strip at the foot of the People page. Nothing is deleted, nothing nags, and
  the app never asks a bereaved owner to confirm the deletion of a life. The
  one thing it does offer, once, is the memorial album — the photos are already
  tagged.

**Zero pets is zero pixels.** No section toggle is needed because there's
nothing to toggle: every pet surface is gated on the household having a pet.
The entry points in a petless install are "Add a pet" on the People page and
a fourth shortcut on the FTUE's last step — *not* a question on its first
step, where the subject is sections and a pet is not one, and not a step of
its own, which is the persona quiz `ROADMAP.md` §5.4 refuses. The FTUE card
hides itself once this user can see a household pet.

### D-pet-care-radar. The care radar takes a subject, not a user.

`Health::CareRadar` is already the right answer to "what routine care is
booked, on track, due, or untracked" — it just assumes its subject has a login.
It gains a subject: a `User` (today's behaviour, unchanged) or a `Pet`, whose
events are the ones tagged with its lens.

- **Per-species kind registries.** Dog: wellness exam / 12 months,
  vaccinations / 12, dental / 12, parasite prevention / 1 month, grooming /
  6 weeks (`clinical: false`, D-nonclinical-care-kinds — the haircut rule
  applies unchanged), nail trim / 6 weeks. Cat: wellness, vaccinations, dental,
  parasite prevention. **Anything else** — rabbit, bird, reptile, horse — gets
  one generic `wellness` kind and nothing more, because we don't know an
  iguana's cadence and inventing one is the invented-cardiologist failure in
  a smaller costume. Custom kinds (below) cover the owner who does know.
- **This is the sub-month cadence HEALTH.md §3 parked.** It said whole-month
  intervals round a six-week haircut badly and that sub-month waits for a
  second kind that wants it; monthly preventatives and a six-week groom are it.
  The registry's `interval_months:` becomes an `interval:` duration
  (`12.months`, `6.weeks`) and `due_on` becomes `last_visit_on + kind.interval`
  — one method, no branching, human kinds unchanged in behaviour.
- **The human radar must exclude pet events, or it lies.** "Rex — dental
  cleaning", tagged Health, currently classifies as *your* dental and reports
  you're on track. One clause excludes events tagged to any pet lens from a
  user's radar; the pet's radar reads exactly those. The reciprocal pair is the
  whole fix, and it gets a test with that exact title.
- **Tuning.** W2 ships registry defaults only. Mute/interval/custom kinds for
  pets means making `care_settings.subject` polymorphic — mechanical, and it
  waits until someone asks, per the same discipline that shipped three human
  kinds before four.
- **Household care already has the shape.** The Health page's household strip
  shows other members' radars over exactly what they share; pets join it as
  rows that need no login — "Rex: vaccines due", "Maya: dental booked Mar 4",
  one strip, whoever's driving.
- **The vet is a Person** with relationship "Vet", so it's already in the
  Address Book, already callable, already attachable to the appointment. "Find
  a vet" is `find_care` with the specialty prefilled — no new tool.

### D-pet-food-shelf. Food is structured, because unlike medications it computes.

D36 made a medication a `Note` with `kind: "medication"` on the grounds that
the med list is prose nobody does arithmetic on. Food is the opposite: what the
user actually wants from it is two numbers.

`pet_foods` rows carry pet, name, brand, form (dry / wet / raw / treats /
prescription), amount per day + unit, package size + unit, package cost,
`started_on`, `ended_on`. Two things derive and nothing else:

- **When the bag runs out.** Package ÷ daily amount = days per bag, so
  "reorder around 14 March" is subtraction, not a guess. Accepting it writes an
  all-day Event, which means the renewal radar gives it lead time and the
  calendar shows it — no new reminder machinery.
- **What it costs a month.** Summed across active foods, this is a real number
  for the Pets envelope's target, offered to the budget and never written over
  a target the user set by hand (D16's hand-set guard).

Ending a food rather than editing it keeps a **diet history**, which is the
thing that's actually asked for: "what's she eating, and since when?" is the
first question at every vet visit and the entire content of an elimination
trial. Superseding is one click.

What the food shelf deliberately doesn't do: calculate portions from breed and
weight, compute calories, or rate a food's quality. Those are a vet's numbers
and a fight the internet has been having for twenty years; the bag states a
feeding amount and the app can hold *the bag's* number. We track what you
decided and what it costs.

---

## 3. Where a pet shows up (the whole point)

| Hub | What appears | Built on |
|---|---|---|
| **People** | A pet card in the same grid as groups and the circle (avatar, "Dog · 4 yrs", one line of signal: next appointment, else food running low, else birthday). Pets are family; this is the household roster. | D-people-circles' card grid |
| **Health** | Each pet's care radar in the household-care strip; the pet's own radar on its page. Vet visits classify like any other care. | D-pet-care-radar |
| **Money** | A `Pets` envelope (needs); food's derived monthly cost as a suggested target; a one-click `SpendingRule` to file the pet-shop merchant there forever; premium hikes and new recurring charges caught by the watchers that already exist. | D-budget-envelopes, D-spending-mirror |
| **Documents** | Vaccination record, adoption papers, microchip registration, insurance policy, lab results — uploaded, summarized, tagged `Health + Rex`. A coverage card on the pet page reuses the `Health::Coverage` heuristic against pet policies. | The vault, unchanged |
| **Photos / Travel** | Photos tagged with the pet's lens: a strip on the pet page, a filter in the library. Vision captions already suggest sections — a caption reading "a golden retriever on a beach" can *suggest* the Rex lens, never apply it (the trust ladder). | `Photo` is `Sectionable` |
| **Calendar / Today** | Vet appointments, grooming, reorder dates, medication refills — dated things are Events, and Events are already everywhere. | Nothing new |
| **Tasks / Goals** | "Teach Rex to walk on a leash" is a Goal through the existing breakdown pipeline; the `start_a_practice` brief (tiny, repeatable, frequency over duration) is *exactly* right for training. | D17, Goals::BreakDown |
| **Hobbies** | Dog sports, showing, breeding, aquarium keeping — already user-created lenses. Nothing to build; they simply co-tag with a pet. | D25 |
| **Rights** | A disputed vet bill or a denied insurance claim is Rights → Disputes, same as a human one. Q3's boundary holds unchanged: care here, billing fights there. | insurance_appeal, dispute_letter |
| **Career** | Nothing. Worth saying: not every section gets a pet feature, and inventing one for symmetry would be noise. | — |

---

## 4. The pet page

One primitive, one page: `/pets/:id`, the place everything converges. The
lens's own section page (`/sections/rex`) stays what section pages are — the
raw browse of everything tagged — and the pet page links to it as "Everything
about Rex". Two surfaces, two jobs, no duplication.

Anatomy, top to bottom (D18's section anatomy, applied to a primitive page):

1. **Header** — avatar, name, species · breed · age (from date of birth,
   hedged to "about 4" when estimated), the vet as a contact, microchip number
   behind a copy button, and the sharing state.
2. **Care radar** — the tiles, every state with its next click, exactly as
   Health's.
3. **Food shelf** — what she's on, since when, what it costs, when to reorder;
   the ended rows collapsed into "Diet history".
4. **Medications** — the D36 card, unchanged, filed to the pet's lens.
5. **Coming up** — the next few Events tagged to her.
6. **Papers** — the coverage card and the documents.
7. **Photos** — a strip, linking into the library filtered to her.
8. **Cost of care** — 12 months of the Pets envelope, honest about what a
   ledger can't see (cash, and the grocery run that also contained a bag of
   kibble). Silent when there's no ledger, rather than showing a confident 0.
9. **Act** — the tool cards (§5), prefilled with this pet.

---

## 5. Tools

A **`:pet` input kind** joins `:person`, `:hobby`, and `:document` — tools take
a pet the way `reconnect` takes a person, and everything the model needs
(species, breed, age, weight if known, current foods, current medications,
recent care) rides along from the record instead of being typed.

| Tool | Kind | Shape it copies |
|---|---|---|
| `pet_care` | chat | `check_in` — the standing conversation, with §6's guardrails |
| `vet_visit_prep` | draft | `doctor_visit_prep`, reading the diet history and med list |
| `decode_vet_estimate` | draft | `decode_letter` — an itemized estimate in plain language, with the questions to ask; never a verdict on whether to spend it |
| `compare_pet_insurance` | draft | `compare_plans` — two policies, stated numbers only, the exclusions that actually bite (pre-existing, hereditary, per-condition caps) |
| `new_pet` | plan | A Situation: vet registration, microchip update, supplies, budget line, insurance decision, puppy classes — tasks tagged across Health, Money and the pet's lens, which is the cross-section proof (Q7) in miniature |
| `lost_pet` | draft | The urgent one, and the most valuable: the first-hour checklist, the microchip registry and shelter call list, and a poster draft with the photo and the microchip number the app already has |

"Find a vet" needs no tool — `find_care` with `veterinarian` prefilled, and it
already reads the vault for how the policy works.

---

## 6. The honesty line, in code

The Health rule holds — support and comprehension, never diagnosis — and three
guarantees don't depend on the model behaving:

- **Every `pet_care` session opens with a code-appended emergency notice**: the
  signs that mean go now (collapse, bloat, straining, a cat that can't
  urinate), and the ASPCA Animal Poison Control number. Rendered in the
  transcript, never sent to the model — the 988 pattern from Health §6.
- **Toxic foods are a shipped dataset, not a model recollection.** Chocolate,
  xylitol, grapes, onions, lilies for cats: the list is short, stable, and
  published in the public domain by the FDA and equivalents. It goes through
  the `datasets` layer (D-public-datasets, the `places.csv` pattern) and is
  consulted deterministically, so "can he have this?" is answered by a lookup
  with a call-the-poison-line card attached — not by a model that is right 98%
  of the time about something with a fatal tail.
- **Every session carries a find-a-vet card**, authored by code. The model can
  say the words; the card makes them one click.

Deliberately not built, and not later either: breed-based health predictions,
symptom triage that outputs a likely condition, dosage arithmetic, and anything
that would let the app be the reason someone waited.

---

## 7. Sharing

A pet is usually *the household's*, not one member's — which makes it the
clearest case yet for the sharing model, and the place to be most careful not
to smuggle in a default.

The pet form offers one checkbox: **"Everyone in the household looks after
Rex."** Ticking it writes explicit rows — an item grant on the `Pet` and a
section grant on its lens, per member — which appear in Settings and are
revocable there like any other grant. Unticked, the pet is private like
everything else. Nothing is implied by the household relationship itself; the
grant rows are the truth, and they're visible (D9).

---

## 8. Waves

**W1 — the pet and its lens.** `Pet` model + migration, the lens created and
renamed with it, `Panels::PetLens` and the resolution rung, `PetsController`
and the pet page (header, coming up, everything-tagged link), the People page's
pet cards and the Remembered strip, the household-sharing checkbox. Nothing
clever; after this, every existing surface can already be told an item is about
Rex.

**W2 — care.** `Health::CareRadar` takes a subject; the species registries; the
interval-as-duration change; the exclusion pair; the radar on the pet page and
in the Health household strip; `find_care` prefilled with `veterinarian`; the
vet as a Person relationship.

**W3 — food and money.** `pet_foods` + the shelf card + diet history; the
derived reorder Event and monthly cost; the Pets envelope offer and the
merchant rule; the cost-of-care card.

**W4 — papers and pictures.** The coverage card over pet policies; the photo
strip and the caption-driven lens *suggestion*; the memorial album offer.

**W5 — tools and watchers.** The six tools, the `:pet` input kind, §6's
guardrails and the toxics dataset; `pet_care_cadence` (checkup_cadence
generalized to subjects) and `pet_food_reorder`. Medication refills, insurance
renewals, and price hikes need no new watcher — they're already covered the
moment the items exist.

Each wave is shippable and useful alone. W1 alone gives a household a place to
keep its pets; W1+W2 is already better than the vet's app, because it knows
about the pets the vet has never seen.

---

## 9. Deliberately not built

- **Weight and other metric streams (Q-pet-metrics).** A weight log is a chart,
  and a chart is a new primitive with no other consumer — the same argument
  that defers wearables in Health §2. Weight-for-age curves would also be a
  health claim. Revisit if the food shelf or a vet-prep tool proves it needs
  the number.
- **A pet-sitter share (Q-pet-sitter).** "Here's everything you need for the
  weekend" is a real want and `D-share-link` (read-only links for people with
  no account, built for recipes) is exactly the machinery. It waits because the
  care sheet it would share doesn't exist until W2/W3.
- **Vet portal / practice-management integration.** The Health §2 verdict
  applies unchanged and worse: per-practice, no standards, aggregator
  territory. Documents and manual capture are the honest floor.
- **Automatic identification of which pet is in a photo.** The `photo_people`
  rule (D-photos-primitive: no face recognition, Q8's lesson) applies, and a
  model confidently tagging the neighbour's dog as yours is the same cost.
  Captions may suggest; a human applies.
- **Multi-household pets** (co-parented dogs, a shared barn horse). One
  instance, one household — the same boundary as everything else.

---

## 10. Files (planned)

| Concern | File |
|---|---|
| The record | `app/models/pet.rb`, `db/migrate/*_create_pets.rb` |
| Its lens | `app/services/pets/lens.rb` (the `People::Group` shape) |
| Pet page | `PetsController`, `app/views/pets/` |
| Lens page | `app/services/sections/panels/pet_lens.rb` + partial |
| Panel rung | `app/services/sections/panel.rb` (shared — its own commit) |
| Care | `app/services/health/care_radar.rb` (subject), `app/services/pets/care_kinds.rb` |
| Food | `app/models/pet_food.rb`, `app/services/pets/food_shelf.rb` |
| Money | `app/services/pets/cost_of_care.rb` |
| People page | `app/services/sections/panels/people.rb` (pet cards, Remembered) |
| Tools | `app/tools/tool/pet_care.rb`, `vet_visit_prep.rb`, `decode_vet_estimate.rb`, `compare_pet_insurance.rb`, `new_pet.rb`, `lost_pet.rb` |
| Guardrails | `app/services/datasets/pet_toxics.rb`, `db/datasets/pet_toxics.csv` |
| Watchers | `app/watchers/watcher/pet_care_cadence.rb`, `pet_food_reorder.rb` |
| Registries touched | `Tool::SLUGS`, `Watcher::SLUGS`, `routes.rb`, `User has_many`, `ICON_PATHS`, fixtures |

---

## 11. What the build changed

Four corrections, kept because each of them was invisible from the plan and
obvious from the code.

**A pet's lens is created, never found.** `Sections::Lens.find_or_create!` is
right for a group — typing "Church" twice means the same church — and wrong
for a record that *owns* its lens: the second dog called Rex tried to take the
first one's section and hit the unique index. `Sections::Lens.create!` joins
it, and the second Rex takes `rex-2`. The case is not hypothetical, and it is
not usually two live dogs: it is one remembered and one new.

**A pet's care is whoever booked it.** The plan inherited "own events only"
from HEALTH.md without noticing it inverts for animals. A spouse's shared
appointment is not your checkup — but the spouse who drove the dog to the vet
booked the *dog's* visit, and there is only one dog. A pet's radar therefore
reads every visible event tagged with her lens, and a shared pet's page grew
the reciprocal share button, because grants are per-grantor and one shared
calendar takes each member sharing their own side.

**No opened date, no reorder claim.** The plan had the food shelf counting a
bag from `started_on`, which drifts the reorder date a bag further out every
month. `opened_on` is its own column, blank is allowed, and blank means the
app says nothing rather than something wrong. The form prefills today where
the value is on screen and can be cleared — a default the user can see beats a
default behind their back.

**Three deletion paths, found by asking what else deletes this.** Removing a
contact who was a pet's vet died on a foreign key (`Person has_many :patients,
dependent: :nullify` — the address book is not a claim about the dog).
Removing a *household member* destroyed their pets but left every lens behind,
because the lens cleanup lived in the controller rather than on the model; it
is an `after_destroy` now, so every path removes both. And a bag and a daily
amount shared one unit column, so a 12 kg sack entered as "12" with the daily
amount in grams produced a confident reorder date of *today* — the bag carries
its own `package_unit`, and a package that would not last a day now says
nothing at all rather than something wrong.

**Panels curate the Act zone, so the controller never learned about pets.**
`Tool.for_section` flows a tool registered on a parent down to every child,
which put "My pet is missing" on the book club's page and "Prep for a vet
visit" on a petless Health page. The gate is `Pets.hidden_tool_slugs` read by
four panels (D37's `hidden_tool_slugs`), and the shared three files stayed
shut. The one shared file that did change is `Sections::Panel`, which grew the
owned-lens rung the plan predicted, plus `Section#removable?` — because
without it the generic "Remove this group" button sat on Rex's lens page and
would have orphaned her.

**The lens now says whose it is (D-owned-lens).** Each fix above was one more
surface remembering to ask the pets table "is this child of People a pet?",
and the ones that forgot kept treating the cat as a group: a vet contact was
offered "Add to group → Dimitri", Settings listed her as an area of People,
chips read "People · Dimitri", and switching People off took her out of every
form's picker. `sections.owner_type` is written when the lens is created, and
groups, subsection lists, name lookups, labels and the picker all read it.
