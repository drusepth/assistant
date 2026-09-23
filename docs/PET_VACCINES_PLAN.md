# PET_VACCINES_PLAN.md

Build plan for **pet vaccination records**: what a pet was vaccinated against,
when, with what, by whom, until when — kept well enough that the page *is* the
pet's vaccine card, and the app can say "Rex's rabies runs out June 3" a month
before it does.

Decision: **D-pet-vaccinations**. Builds on D-pet-primitive,
D-pet-care-radar, D-landing-registry, D-share-link, D-suggestion-lifecycle.

**Status: built, W1–W4** (2026-09). §12 records what the build changed about
the plan.

---

## 1. The problem

The pet page's Routine care card has a "Vaccinations" tile. Its "Log the last
one" link opens a plain New event form titled "Rex — vaccinations". That
records *that a visit happened*, and nothing about it that anyone later asks
for:

- **Which vaccines.** One visit gives three or four shots, and each has its
  own lifetime: a dog's rabies may be good for one year or three depending on
  the product and local law, the core combo (DHPP) is often three years after
  the puppy series, kennel cough is six to twelve months, leptospirosis is a
  year. The tile runs a single 12-month clock, so it is wrong about most
  pets most of the time.
- **Proof.** The boarding kennel, groomer, daycare, dog licence, landlord and
  airline all ask the same question — *is rabies current, and show me* — and
  want the certificate or the tag number. An event's free-text description can
  hold that but nothing reads it back, and nothing can show it to the kennel.
- **History that matters medically.** "Swelled up after the lepto shot in
  2024" is the single most useful sentence in a pet's vaccine history, and
  there is nowhere to put it where the next vet visit will see it.
- **Guessing.** The tile finds vaccination visits by matching words in event
  titles (`/vaccin/`, `/shots?/`, `/rabies/`). That is exactly the mechanism
  D-no-keyword-logic retires. An explicit record says what it is.

An event stays the right shape for the *appointment* — it is dated, it is on
the calendar, it is what you book. What was *given* at it is a different
thing, with different fields and a different clock per item, and it needs a
record of its own.

## 2. The record: `PetVaccination`

One row per **dose given** (or titer drawn, or exemption issued — §2.2) per
pet. Modelled on `PetFood`: a child of the pet, visible exactly when the pet
is, exported with its owner.

| column | type | notes |
|---|---|---|
| `pet_id` | ref, not null | visibility, export and deletion all follow the pet |
| `user_id` | ref, null | who logged it (a spouse can log for a shared pet — §7); nulled if they leave the household, so the pet keeps her history |
| `kind` | string, not null | `dose` · `titer` · `exemption` (§2.2) |
| `vaccine_key` | string, null | a catalog key (§3) — `nil` for a vaccine the catalog doesn't know |
| `name` | string, not null | as printed ("Nobivac 3-Rabies"), or the catalog label when picked from the list |
| `given_on` | date, not null | the date on the certificate; titers: the draw date |
| `due_on` | date, null | **good until / next dose due** — the certificate's date wins (§4) |
| `duration_months` | integer, null | what the owner picked ("3 years") when the certificate gave no date; `due_on` is computed from it and stored |
| `vet_id` | ref → Person, null | the clinic, as an ordinary contact (the pet's vet by default) |
| `administered_by` | string, null | the vet's name as printed, when it isn't a contact |
| `product` | string, null | brand/manufacturer ("Merck Nobivac") |
| `lot_number` | string, null | recall lookups and some certificates require it |
| `tag_number` | string, null | rabies tag / certificate number — the thing licensing asks for |
| `site` | string, null | where it was given ("left hind leg") — vets record this for cats (injection-site sarcoma) and owners are asked for it |
| `series_dose` | integer, null | 1, 2, 3 for a puppy/kitten series; `nil` for a booster |
| `reaction` | text, null | a reaction, in the owner's words — **surfaced as a warning** (§5.3) |
| `notes` | text, null | anything else |
| `document_id` | ref → Document, null | the certificate in the vault |
| `event_id` | ref → Event, null | the visit it was given at |

Indexes: `(pet_id, vaccine_key, given_on)`, `(pet_id, due_on)`.

Validations: `given_on` not in the future (you log what happened; a future
dose is an appointment, an Event); `due_on` after `given_on`; `kind` in the
closed set; `vaccine_key` in the catalog for the pet's species or nil; `name`
present.

### 2.1 Why one row per dose, not one row per vaccine

The history *is* the record. A vet asks "when was her first FVRCP, and has
she had the boosters?"; a recall notice names a lot; a reaction belongs to a
specific dose. A per-vaccine row with a "last given" column throws all of
that away on every update. "What is current" is a query over doses (§4), not
a column someone has to keep right.

### 2.2 Titers and exemptions

Two real alternatives to a dose that owners of older and sicker pets live
with, and that boarding kennels and some jurisdictions accept:

- **Titer** — a blood test showing immunity, used in place of a booster
  (commonly for distemper/parvo). It has a draw date, a result, and usually a
  "valid until". Same row, `kind: "titer"`; the result goes in `notes`.
- **Exemption** — a vet's written waiver ("medically exempt from rabies
  vaccination"), which in many places has an expiry of its own. Same row,
  `kind: "exemption"`.

Both count toward "is this vaccine covered, and until when" (§4) and both
print on the shareable record labelled for what they are. Storing them as
doses would lie on a document a stranger relies on; leaving them out would
make the app useless for exactly the pets whose owners most need the record.

## 3. The vaccine catalog: `Pets::Vaccines`

A code registry, per species — the same "we only claim what we know" rule as
`Pets::CareKinds`. It exists so the form can offer a checklist instead of an
empty box, so two doses of the same vaccine under different printed names
("Rabies 3yr", "Imrab 3") are recognisably the same vaccine, and so the pet
page can say which *core* vaccines have no record at all.

Each entry: `key`, `label`, `also_called` (for display help — **never
matched against text**, D-no-keyword-logic), `core` (true / false / `:kittens`
style notes as copy only), and `durations` — the lifetimes products are
labelled for, offered as buttons, never assumed.

- **Dog** (AAHA): *core* — rabies (1 or 3 yr), DHPP/DAPP distemper-adenovirus-
  parvovirus-parainfluenza (1 or 3 yr); *lifestyle* — leptospirosis (1 yr),
  bordetella / kennel cough (6 or 12 mo), canine influenza (1 yr), Lyme (1 yr).
- **Cat** (AAFP): *core* — rabies (1 or 3 yr), FVRCP (1 or 3 yr); FeLV (core
  for kittens, lifestyle for adults; 1 or 2 yr); *lifestyle* — bordetella,
  chlamydia.
- **Horse** (AAEP): *core* — tetanus, EEE/WEE, West Nile, rabies (1 yr);
  *risk-based* — influenza, rhinopneumonitis/EHV (6 or 12 mo), strangles,
  Potomac horse fever, botulism.
- **Rabbit**: RHDV2 (1 yr), myxomatosis (region-dependent; 1 yr).
- **Bird, reptile, fish, other**: **no catalog.** The form is free text only,
  and nothing on the page claims a vaccine is missing.

Core/lifestyle labels are the professional bodies' guidance, stated as such
in copy ("AAHA lists rabies and DHPP as core for dogs"). Legal requirements
(rabies rules differ by state and country) are **not** encoded — the app
does not know the household's jurisdiction's law and must not pretend to.

A dose of something not in the catalog is fine: `vaccine_key: nil`, the
printed name is the identity, and doses group by name (case-insensitive) for
"current" purposes. Grouping by exact name is deterministic string equality,
not classification.

Adding a species or vaccine is one entry in `Pets::Vaccines`, with its source
cited in a comment.

## 4. What "current" means

For each vaccine a pet has any record of (grouped by `vaccine_key`, else by
normalized `name`), the **latest** row by `given_on` decides:

| state | when |
|---|---|
| **Current** | latest `due_on` is more than 30 days out |
| **Due soon** | latest `due_on` is within 30 days |
| **Overdue** | latest `due_on` has passed |
| **Booked** | overdue or due soon, *and* a future vaccination visit is on the calendar (§5.4) |
| **No expiry recorded** | latest row has no `due_on` — shown honestly, never guessed |

Plus, for species with a catalog: **core vaccines with no record at all**
listed as "No record of rabies" — a gap, not an alarm.

`due_on` precedence, in the form and in intake:
1. the date printed on the certificate ("expires", "next due", "valid until");
2. the duration the owner picks from the catalog's buttons → `given_on + duration`;
3. nothing — the row is saved with no expiry, and the state says so.

The app never fills in a duration on its own. A three-year rabies logged as
one year sends a reminder two years early; a one-year logged as three means
a pet boarding illegally. Only the certificate or the owner knows.

Series doses (puppy/kitten shots every 3–4 weeks) use the same `due_on` for
"next dose due" — the reminder machinery doesn't need to know it's a series.

## 5. Surfaces

### 5.1 The pet page: a Vaccinations card

Replaces the Vaccinations tile in Routine care (the tile's kind is removed
from `Pets::CareKinds`, so the radar and `PetCareCadence` stop reading event
titles for vaccines). Lives in the main column below Routine care.

- One row per vaccine: name, state chip, "Good until Jun 3, 2028" / "Due
  Mar 12" / "Overdue since Jan", last given date, tag number if any, a
  paperclip if a certificate is attached. Tap → the vaccine's history (every
  dose, newest first, with product/lot/site/vet/reaction).
- A reaction on any dose shows as a warning line on the card: "Reacted to
  Leptospirosis (Mar 2024): facial swelling" — never collapsed.
- Missing core vaccines as a quiet line under the list.
- Actions: **Log vaccines** (the form, §5.2), **Upload a certificate**
  (intake, §6), **Share the record** (§5.5).
- Empty state for a dog/cat: "No vaccine records yet. Log the last visit, or
  upload the certificate and the app will read it."

### 5.2 The log form: one visit, several vaccines

`/pets/:pet_id/vaccinations/new` — the shape of a real visit, not one row at
a time:

- **Visit** fields once: date given, vet (the pet's vet preselected; any
  contact; or a typed name), optional link to an existing visit Event (the
  form offers the pet's recent past events tagged with her lens), certificate
  upload or pick-from-vault.
- **Vaccines** as a checklist from the catalog for her species, each ticked
  one expanding to: good-until date *or* duration buttons, product, lot, tag
  number, site, series dose, reaction, notes. "Add another vaccine" for free
  text. Species with no catalog: free-text rows only.
- A `kind` switch per row for titer / exemption.
- Saving writes one `PetVaccination` per ticked row in a transaction, all
  sharing the visit's date, vet, event and document.
- Editing is per row (`/pets/:pet_id/vaccinations/:id/edit`); deleting is per
  row with a confirm.

The care radar's old "Log the last one" link on Vaccinations goes here, and
so does a new "Log vaccines given at this visit" link on any past Event
tagged with a pet's lens.

### 5.3 Where vaccine history is read

- **Tools** — `pet_care`, `vet_visit_prep`, `compare_pet_insurance`, and
  `lost_pet` get the pet's current vaccines and any reactions in their pet
  context (the rabies tag number is on the lost-pet sheet; reactions lead the
  vet-visit prep: "Tell the vet: she reacted to the lepto shot in 2024").
- **Chat / assistant context** — the same pet context block.
- **Health page household-care strip** — "Rex: rabies due Jun 3" beside the
  humans' rows, from §4's states.

### 5.4 Reminders: `Watcher::PetVaccineDue`

The point of the whole thing. A new watcher, same base as `PetCareCadence`,
over `Pet.visible_to(user).active`:

- Proposes when a vaccine enters **due soon** (30 days out) and again when
  **overdue**, per pet per vaccine per `due_on` —
  fingerprint `"#{pet.id}/#{group_key}/#{due_on}"`, so a new dose (a new
  `due_on`) is a new conversation and a dismissed one stays dismissed for
  that due date.
- Title / body: "Rex's rabies runs out June 3" · "Logged Jun 3, 2025, good
  for 3 years. Nothing is booked." Several vaccines due within the same 30
  days collapse into one proposal ("Rex has rabies and DHPP due in June") —
  one vet visit, one nudge.
- Action: the new-event form prefilled "Rex — vaccinations (Rabies, DHPP)",
  tagged Health + her lens, and carrying `care_kind: "pet_vaccinations"` —
  the explicit field the radar already had — so the card flips to **Booked**.
  No vet on file → the action is `find_care` instead.
- **Retires itself** (D-suggestion-lifecycle) when a newer dose of that
  vaccine is logged, when a linked appointment is booked, or when the pet
  stops being active.
- No `due_on`, no nudge. No record, no nudge. Guessed nudges cost trust
  (the Q8 lesson).
- Honors the Health section's agent dial like every watcher; notifications
  ride the existing channels.

### 5.5 The shareable vaccine record

The one-sheet the kennel wants: pet name and photo, species/breed/sex/
spay-neuter, microchip, current vaccines with given/good-until dates, tag
number, titers and exemptions labelled as such, vet name and phone, and the
certificates as downloadable files. **Never** reactions, notes, weight,
cost, or anything else on the pet page unless the owner ticks it.

- **Print view** (`/pets/:id/vaccinations/record`) with a print stylesheet —
  the zero-infrastructure answer.
- **Share link** — `Pet` joins `ShareLink::SHAREABLE_TYPES`, and a Pet link's
  public page renders the vaccine sheet and nothing else of hers. This widens an
  unauthenticated read path, so it is its own decision line in
  D-pet-vaccinations: the link shows exactly the print view's fields, the
  owner picks an expiry (the kennel needs it for a week), it is revocable,
  and view counts show in the owner's list like recipe links do.

## 6. Intake: `Landing::PetVaccination`

A rabies certificate or a clinic invoice is the most common pet document
there is, so the landing registry gets a kind for it — one entry per dose,
nothing lands without the click, the file is always kept (D-document-intake).

Fields: `pet` (ref, required), `vaccine` (choice over the catalog keys for
the resolved pet's species, plus "other"), `name` (as printed, required),
`kind` (choice), `given_on` (date, required), `due_on` (date, only if
printed), `product`, `lot_number`, `tag_number`, `administered_by`, `site`,
`series_dose`. **Not** `reaction` or `notes` — those are the owner's words.

The model maps printed names to catalog keys *inside the closed set* — that
is classification by the model over a bounded list, which is what
D-no-keyword-logic asks for. `duplicate_of` matches pet + vaccine group +
`given_on`, so re-uploading the same certificate proposes nothing new. The
landed rows get `document_id` set to the uploaded document automatically.

`Landing::Event` keeps landing the *visit*; the review page shows the event
and its doses together.

## 7. Privacy and sharing

- A vaccination is visible exactly when its pet is — no grants of its own.
  A spouse the pet is shared with can read the record and log doses (`user_id`
  records who), the same model as a pet's food shelf.
- Export: `"pet_vaccinations"` in `Users::Export::MODELS`, next to
  `pet_foods` — it is the half of the pet record a new vet asks for.
- A certificate `Document` keeps its own visibility; the vaccination card
  shows the paperclip only to viewers who can see the document.
- The share link (§5.5) is the only path outside the household, and it is
  owner-made, narrow, expiring, and revocable.

## 8. Migration of what's already there

Existing events the old tile counted as vaccinations can't be turned into
doses — we don't know what was given, and parsing titles is the thing we are
removing. Instead: if a pet has past lens-tagged events whose `care_kind` is
`pet_vaccinations` (or which the old radar classified that way at migration
time — computed once, in the migration, as a list of event ids), the new
card shows "You logged vaccination visits on Jun 3, 2025 and May 1, 2024 —
add what was given", each linking to the log form prefilled with that date
and event. Nothing is invented; the owner fills in what they know.

`pet_vaccinations` leaves `Pets::CareKinds`. `care_kind: "pet_vaccinations"`
stays a valid stored value so old overrides don't break.

## 9. What we are not doing

- **Encoding local law.** No "rabies is required every 3 years in Ohio".
- **Recommending vaccines.** The catalog shows the professional bodies'
  core/lifestyle labels as reference; it never says "Rex should get Lyme".
  That is the vet's call.
- **Defaulting durations.** §4.
- **Integrating with clinic systems.** No vet-practice APIs; paper and photos
  are the universal interface, and intake reads them.
- **Human vaccinations.** Same shape would work; it is a separate decision
  under Health, not part of this build.

## 10. Build waves

**W1 — the record.** Migration, `PetVaccination` model and validations,
`Pets::Vaccines` catalog, `Pets::VaccineStatus` (§4), the log form (§5.2),
per-row edit/delete, the Vaccinations card (§5.1), removing the Vaccinations
kind from the radar with the §8 migration prompt, export. Tests: model
validations, status computation (every state, titers, exemptions,
free-text grouping), visibility (a shared pet's doses visible, an unshared
one's not), controller happy path and the transaction, export.

**W2 — reminders.** `Watcher::PetVaccineDue` with collapse, retirement, and
the booked link (`events.vaccine_keys`); household-care strip rows; "Log
vaccines given at this visit" on past pet events. Tests: fingerprint
stability, retirement on new dose / booking / death, collapse window, dial.

**W3 — intake.** `Landing::PetVaccination`, review-page grouping, certificate
link on landing. Tests: the registry drift guard, closed-set validation of
`vaccine`, duplicate suppression, document link.

**W4 — the record leaves the house.** Print view, share-link subject,
tool/chat context and reactions in visit prep, About page copy. Tests:
share link shows only the allowed fields, expiry and revocation, tool
context includes reactions and tag number.

Each wave is shippable on its own; W1 alone already answers the original
complaint.

## 11. Open questions

- **Q-pet-vaccine-humans** — does the same record serve human immunizations
  (tetanus boosters, travel shots) under Health? Likely yes, as a separate
  subject on the same shape; not decided here.

## 12. What the build changed

- **No `events.vaccine_keys` column.** A booked visit is an event carrying
  `care_kind: "pet_vaccinations"` — an explicit field the event already had
  and the owner can already set from the event page. One visit covers
  whatever is due, which is what a visit does; per-vaccine booking would
  have been a second column to keep right for no reader.
- **The old events were marked once, in a migration.** Pet events the
  retired tile counted as vaccinations got `care_kind: "pet_vaccinations"`
  written down (`MarkPetVaccinationVisits`) — the last time the old title
  patterns run. That is what lets the card list them as "add what was given"
  and what keeps them from falling through to the wellness kind on "vet".
- **The share subject is the Pet**, not a pseudo-model standing for "her
  vaccine record". The allowlist comment says a Pet link shows only the
  sheet, and the public controller renders only the sheet; a pseudo-model
  would have been a second name for the same row. Certificates behind the
  link are streamed through the token (`/s/:token/certificates/:id`) rather
  than linked by blob URL, so revoking the link cuts off the files too.
- **Lead window decided** (was Q-pet-vaccine-lead): 30 days, or a third of
  the dose's own interval when that is shorter, so a puppy's three-week
  booster isn't "due soon" the day it was given.
- **No ferret list.** A ferret is "other" in `Pet::SPECIES`, and the catalog
  keys off species; guessing that an "other" is a ferret is the claim the
  catalog exists not to make.
- **Who may write.** Anyone the pet is visible to can log a dose (the person
  at the vet holds the paper); a dose is edited or removed by whoever logged
  it or by the pet's owner. The food shelf stays owner-only — a diet is a
  decision, a dose is a fact about a visit.
- **Pet foods got a route resolver too.** The document page's "Saved from
  this document" list calls `link_to item`, which had no route for a
  `PetFood`; the resolver that sends a dose to her record sends a food to her
  page.

