# HEALTH.md

The Health section deep-dive (the Hobbies-doc pattern, D25 → D30): what
"an assistant that takes care of your health" means for the 99%, what data
can actually feed it, and the build that follows.

## 1. The thesis: logistics, not biometrics

What a personal assistant actually does for someone's health is mostly not
medical: they make sure the checkup is booked, remember when the last one
was, keep the insurance paperwork findable, sit on hold with the insurer,
and prep you for appointments. That is the job here — and every piece of
it is Tier A (owned data + any model), high-frequency, and universally
needed. The carefully-kept scope line from PRODUCT.md stands everywhere:
**preparation and comprehension, never diagnosis.**

The at-a-glance promise has two halves, and both matter:

- **"You're due"** — surface what needs attention before it's missed.
- **"You're booked — stop thinking about it"** — the quiet half. An
  assistant that can only nag adds anxiety; one that can say *handled*
  removes it.

## 2. Data sources: the honest landscape

What could feed a Health section, surveyed so we stop re-litigating it:

| Source | Reality | Verdict |
|---|---|---|
| **Google Fit** | REST API shut down (2025). Its successor, **Health Connect**, is an on-device Android store with no cloud API — reading it requires shipping a native Android app. | Not available to a self-hosted web app. Deferred indefinitely. |
| **Apple Health** | No cloud API. Data leaves the phone only as a manual `export.xml` file export. | Feasible later as a file importer — one parser class in the existing `Events::Import`/`People::Import` registry pattern. Not v1. |
| **Fitbit / Garmin / Oura / Withings** | Real cloud APIs behind OAuth. | The genuine wearable path: future `LinkedAccount` providers riding D26 scopes + the D27 relay. Build when a consumer exists that earns it (see §6). |
| **Insurer / provider portals (FHIR)** | CMS-mandated Patient Access APIs and Medicare's Blue Button 2.0 exist, but per-payer registration makes them aggregator territory. | Watch. The self-hostable version of this is genuinely mission-shaped, and genuinely far off. |
| **Calendar (CalDAV)** | **Already syncing** (D26). Appointments are the single highest-value health signal we can get. | Live today — the radar reads it. |
| **The vault + document understanding** | **Already built.** Insurance cards, SBCs, EOBs, lab results — uploaded, extracted, summarized, auto-tagged. | Live today — the insurance tools read it. |
| **Manual capture** | D16 zero-friction forms, radar-prefilled. | Live today. |

The conclusion is D30: **the durable assets are appointments and
paperwork, and the sources that carry them are already connected.**
Metric streams (steps, sleep, heart rate) are deferred — not because
they're worthless but because every honest path to them is either dead
(Fit), device-bound (Health Connect), manual (Apple export), or a
per-vendor OAuth integration; and without a consumer (trends, a
metrics view — a new primitive, D5 pressure) they'd be data with no job.

## 3. The care radar

The Health page's lead panel answers, per kind of routine care: **booked /
on track / due / not tracked**. `Health::CareRadar` is a *derived view* —
deterministic keyword classification over the user's own Health-tagged
events, zero schema — so it can never disagree with the calendar it reads,
and everything that feeds the calendar (CalDAV sync, imports, quick
capture, tool-created deadline events) feeds the radar for free.

- **Kinds registry** (in the service): checkup / 12mo, dental / 6mo,
  vision / 24mo — label, provider (seeds find-care), appointment title
  (seeds event capture), interval, match patterns. Adding a kind is one
  registry entry; per-user kinds/intervals (skin checks, gyn, kids'
  well-visits per member) are the obvious next rung and would need real
  storage — deliberately deferred until the three-kind version proves the
  panel.
- **Conservative classification.** "Dental checkup" is dental (specific
  kinds match before the generic), "Physical therapy" is not a physical,
  and an event the radar can't confidently place ("Therapy",
  "Cardiology follow-up") simply doesn't count — misclassifying would
  make the panel lie, and unknown is an honest, actionable state.
- **Own events only** — a spouse's shared appointment is not your checkup
  (the watcher's rule from M3.1, inherited).
- **Every state has its next click**: booked → the appointment; due /
  not tracked → "Find a provider" (find-care, specialty prefilled) and
  event capture with the title prefilled ("Log a past visit" for
  unknowns — one past-dated event is all the radar needs to start
  tracking a kind).

## 4. The insurance stack

Q3's boundary holds: **coverage and care navigation live here; billing
disputes stay in Rights → Disputes.** Insurance needs no new primitive —
a plan *is* documents, and the vault already understands documents. The
page's coverage card surfaces plan-shaped documents (`Health::Coverage`,
keyword heuristic over title + AI summary, `visible_to` — a spouse's
shared plan is exactly what it should show) with the tools attached,
prefilled with the newest plan docs:

- **Understand my insurance** (`insurance_explainer`, draft) — the plan's
  own stated numbers in plain language; never invents a number
  ([PLACEHOLDERS] name what to look up); disclaimer by code; D28-routes
  onward to find-care or insurance-appeal with the document attached by
  code.
- **Compare health plans** (`compare_plans`, draft) — open enrollment's
  asymmetry problem: two plan documents side by side, stated numbers
  only, scenario reasoning tied to the user's household line.
- **Find a doctor** (`find_care`, draft) — the ROADMAP's canonical Q9
  reframe, finally built: no invented providers, ever; instead the plan
  for finding real ones (the insurer's directory by name when the vault
  knows it, call script, what to weigh), with the verify-in-network
  warning appended by code. This is also the accept-target of the
  per-kind watcher and the radar's "Find a provider" links.

Together with the existing family — decode-letter (the front door),
results-explainer, doctor-visit-prep, insurance-appeal — Health now
covers the full loop: *something arrives → understand it → act on it →
be prepared for the visit → appeal what's wrong.*

## 5. The agent: per-kind cadence

`Watcher::CheckupCadence` grew up (M3.1's generic version → per-kind on
the radar's classification): a kind with history, past its interval,
with nothing booked → "Book a dental cleaning — your last was February;
about every 6 months is the usual rhythm," accept opens find-care
prefilled (the stay-in-touch convention). **Signal discipline:** no
per-kind history means no per-kind nudge — the radar panel is the pull
surface for unknowns, and guessed nudges cost trust (the Q8 lesson). The
zero-signal case keeps the original generic nudge, fingerprints and all.

## 6. Mind: mental health, scoped honestly (D31)

Mental health is the half of Health the target user is least likely to
have professional help with — therapy is expensive, waitlisted, and
stigmatized — which makes it exactly mission-shaped and exactly where
capability honesty matters most. The line, drawn once and enforced in
code where possible: **support, not therapy.** An LLM chat is not a
therapist, and branding it as one is the same capability lie the Tier-A
rule exists to prevent — with far higher stakes than an invented
cardiologist. What ships instead covers what people actually reach for:

- **Check in** (`check_in`, chat kind) — a private place to talk through
  what's on your mind, guided or unguided. Guided modes ride the
  quick-reply chips: unpack a stressor, a breathing/grounding exercise
  walked one step per turn, gratitude/wind-down, and *prep for a real
  therapy session* (the doctor-visit-prep move, applied to therapy).
  "Just listen" is a first-class mode: no fixing, no advice until asked.
  The boundaries live in the system prompt (never diagnose or name
  suspected conditions, no medication advice, encourage a human
  therapist when things sound heavy or persistent) — and the one
  guardrail that must not depend on model behavior doesn't: a
  code-appended crisis notice (988 / local crisis line) opens every
  session, rendered in the transcript, never sent to the model. Recap
  Notes (explicit save, D20) file under Health and feed the next
  session's prompt — continuity without surveillance, the owned-memory
  moat again.
- **Start a calm practice** (`start_a_practice`, plan kind) — meditation,
  yoga, walks, journaling as a paced Goal through the shared breakdown
  pipeline. The brief is the start-a-hobby discipline tuned for
  practices: tiny and repeatable over ambitious, frequency over
  duration, first session within days, nothing to buy, pain is a stop
  sign. Sessions land as scheduled steps — which means the calendar, the
  Today page, and (if it ever earns one) a practice-cadence watcher all
  see them for free.
- **Find a therapist** — no new tool: find-care already does this
  honestly (specialty prefilled from the Mind card), including reading
  the vault's insurance documents for how the plan handles mental-health
  coverage. The check-in's "this sounds like more than a check-in" road
  points here.

The Mind card on the Health page carries all three, the
pick-your-last-check-in-back-up continuity link, and the
support-not-therapy line in plain sight — the trust ladder applied to
the most trust-sensitive feature in the app.

**Deliberately not built:** mood tracking without an opt-in signal
(guessed mood nudges are the wrong-"call your mom" problem at 10× the
cost — Q8's lesson), any agent nudge *about* mental state (the watcher
may one day notice a practice lapsing, an event; never "you seem
down"), and anything that stores clinical-sounding labels the user
didn't write themselves.

## 7. Later rungs (in rough order of earn)

- **Per-user cadence settings** — track/ignore per kind, custom
  intervals, per-member kinds (kids' well-visits). First thing to build
  when someone asks the radar to shut up about vision.
- **Medications** — the highest-value missing tracker. Likely a
  structured-note pattern + a refill watcher (renewal-radar shaped), not
  a new primitive; needs its own design pass.
- **Symptom journal** — a chat-kind tool (D29, tutor-shaped): log in
  plain language, recap Notes accumulate into exactly what
  doctor-visit-prep wants to read.
- **Apple Health export importer** — one parser in the import registry;
  lands workouts/appointments as Events. The first honest metrics rung.
- **Wearable providers (Fitbit/Garmin/…)** — D26 providers behind D27
  OAuth, once a metrics consumer exists.
- **Practice cadence watcher** — the neglected-hobby move for calm
  practices: sessions were happening, then stopped, nothing upcoming →
  one gentle nudge. Deterministic, event-based, never about mood (§6).
