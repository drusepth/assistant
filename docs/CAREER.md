# CAREER.md

Section deep-dive for **Career** — design for how the section earns its place
across all three modes (D6). Everything here rides existing infrastructure
(D17 breakdown, D19 tools, D20 watchers, D26 linked accounts, D28 routing,
D29 chat) except where explicitly flagged. The one new decision it needs —
how career signal gets into the app — is **D-career-signal** in `DECISIONS.md`; the
external-data questions it raised are resolved as **D-public-datasets**
(local public datasets) and **D-career-web** (the web on three leashes + ask-then-
send). Everything in this document is built, ✅-marked in §7.

## Why this section matters (mission tie)

Career is where the target user sells their time — for most of the 99%, the
single biggest lever on their material life. The asymmetry here is the
mission's thesis in miniature: the employer negotiates compensation every
week and knows the pay band, the market, and your alternatives; the employee
negotiates once every few years and knows none of it. The wealthy close that
gap with recruiters, agents, mentors, and career coaches. The target user
gets a LinkedIn feed and a "we've decided to go another direction" email.

Salary outcomes **compound**: a raise won at 28 is paid every year after.
An interview flubbed for lack of prep costs the whole offer. A layoff
navigated badly cascades into Money, Health (insurance), and Benefits. The
counter-move is the app's usual one — owned context plus tools at the moment
of leverage — applied to the highest-stakes recurring negotiations in the
user's life.

One framing rule, stated up front: this section is **not** a
white-collar-ladder optimizer. The target user is as likely to be an hourly
worker, a gig worker, a tradesperson, or someone with a patchy resume as a
salaried professional. Every tool below has to make sense for "shift lead at
a distribution center" as much as for "senior engineer" — which mostly means:
no assumed resume, no assumed LinkedIn, jargon-free output, and hard respect
for the Tier-A rule that we never invent market facts we can't back.

Design trap to avoid: career tools that quietly become *employer-side*
thinking ("make yourself more attractive"). The app works for the user. The
posture is the negotiation-prep tool's posture, generalized: even the odds,
maximize the value of the user's time, and be honest when the data to do
that has to come from outside.

## 1. Knowing the user's work life (the foundation — D-career-signal)

Everything else needs to know: what the user does, what they're paid, what
they've accomplished, and when compensation last moved. The answer is a
**ladder**: read what the user grants, keep manual logging as the
always-available floor, and never guess. (Q8's actual lesson was about the
last rung — inference from ambient signals produces wrong nudges and wrong
nudges cost trust. It was never a reason to refuse data the user hands
over; a pay stub in the vault is granted access, and reading it well is
the whole point of an assistant.)

### Rung 1 — granted data (read everything you're given)

- **Pay stubs are Documents, and the pipeline already exists.** The vault +
  `AnalyzeDocumentJob` already ingest and summarize them; the upgrade is
  **career-aware extraction**: when analysis classifies a document as a pay
  stub, also extract the structured facts — employer, pay rate, gross/net,
  period, hours, overtime, deductions — and maintain a **comp timeline**
  from them. A detected rate change against the previous stub lands as a
  comp-change Event automatically with its provenance named ("from the
  Mar 15 pay stub" — D16: the assistant does the filing); an ambiguous read
  becomes a suggestion instead (D20: propose when unsure). Upload cadence
  is the user's choice: every payday, or just when something changes.
- **W-2s and tax forms** are annual ground truth: total comp per year,
  year-over-year — the series the real-terms watcher (§4) reads.
- **Offer letters and contracts** already live in the vault; §3.5 gives
  them a specialist decoder.
- **LinkedIn's official data export** (D26 lists LinkedIn as a file-export
  provider; D27 confirms export files are the honest path) bootstraps the
  work-history profile in one upload: positions → the profile Note,
  connections → People. Nobody should retype their own history.
- **Email, when the D26 IMAP consumer lands**: payroll notifications
  (ADP/Gusto/Paychex) feed the comp timeline; application confirmations,
  interview invites, and rejections feed the job-search funnel — the
  application-follow-up watcher stops depending on hand-made Tasks.
- **Bank deposits** are the other paycheck mirror (recurring deposit =
  cadence + net amount). That signal arrives when Money grows its
  transactions layer (statement import / open-banking — Money's own
  deep-dive, not this one); Career should consume it then, not block on it.

Sensitivity note, named because pay data is the most guarded number in most
households: all of this is ordinary primitives under D9 — **private by
default**, invisible to other members until explicitly shared, and the
cross-user watchers never read it unshared. The comp timeline is exactly as
shareable, exportable (M4), and deletable as everything else the user owns.

### Rung 2 — manual logging (the always-available floor)

Not everyone will upload stubs or link email, and the floor has to serve
them fully:

- **Comp-change Events.** A raise, a promotion, a job change, an annual
  review: one tap, a Career-tagged all-day Event ("Raise: $19 → $21/hr").
  Manual and extracted entries form one timeline; manual wins conflicts
  (the user knows better than the parser).
- **The win log.** Quick-capture Career-tagged Notes: "caught the inventory
  error before the audit", "covered the closing shift six weeks straight",
  "shipped the migration". Day-one capture cost: one line (D16 — the
  categorizer files it). Payoff: the raise case and every resume tailor and
  interview prep *builds itself* from receipts, instead of the user trying
  to remember two years of work the night before a review. This one stays
  manual-first on purpose — accomplishments live in the user's head before
  they live in any system — though granted sources can *suggest* wins
  ("that praise email from your manager — log it?") once email lands.
- **The rest is ordinary primitives**: resume/CV in the vault (Document),
  a work-history/skills/current-comp Note ("Tell me about your work" — the
  same interview-capture pattern as the hobby profile), certifications and
  licenses as Events with expiry dates (renewal radar already watches those
  for free), applications and interviews as Tasks/Events as they happen.

### Rung 3 — never guessed

The Q8 discipline, kept where it actually applies: the app never presents
an inferred number as fact, and a nudge always cites its source ("your
last comp change was the Mar 15 stub" / "you logged this raise"). No
granted signal and no logged signal → no nudge, only a one-time invitation
to start the habit or upload a stub.

Tools read all of this through the existing `section_context` — the
negotiation-prep tool already does, so a user with a win log or a stub
history gets a better prep sheet *today*, before anything below is built.

## 2. Organize (mostly already built — name it, don't build it)

The lens dividend again — Career-Organize fell out of Milestone 1:

| Life thing | Primitive |
|---|---|
| Resume, offer letters, reviews, pay stubs, W-2s, contracts | Documents |
| Interviews, review meetings, cert expirations, comp changes | Events |
| Applications, follow-ups, "update the resume" | Tasks |
| Job search, promotion push, career change | Goals + steps |
| Managers, references, former coworkers, recruiters | People |
| Win log, work-history profile, per-company research | Notes |

Notable freebies already live: decode-this-letter triages scary employer
mail (a PIP, a severance agreement, a non-compete) from any document page;
renewal radar covers license/cert expirations; goal-stall covers a stalled
job hunt; Learn-something handles "study for the CDL" and files it under
Education + Career.

## 3. Tools (the meat — each rides D19/D28/D29 infra)

All Tier A (owned data only) unless flagged. Ordered by the moments they
serve, funnel-widest first.

### 3.1 "Prep me for an interview" (draft) + "Mock interview" (chat)

The highest-frequency high-stakes moment, split the tutor way:

- **Interview prep** (draft): inputs are the job listing — pasted text or a
  vault Document; the app fetches a URL for you, see §5 — plus optional
  "what worries you". Context: resume Document, work-history Note, win log.
  Output lands as Notes: a prep sheet (what this role actually wants,
  translated from the listing's jargon; which of *your* logged wins answer
  each requirement, as tellable stories; the likely questions with the
  trap ones flagged; smart questions to ask them; logistics checklist) and
  a separate research checklist naming exactly what to look up about the
  company — never invented facts about it (Tier-A honesty; the model knows
  interviewing evergreen-well, it does not know this week's news about
  Acme). Routes (D28) onward to the mock interview with the same inputs.
- **Mock interview** (chat, rides D29 exactly like the tutor): the model
  plays the interviewer for the pasted listing, one question at a time,
  coaches after each answer (what landed, what to tighten, where a win-log
  story would have been stronger), adapts difficulty, switches personas on
  request ("now be the skeptical operations manager"). "Save a recap" lands
  the debrief Note — what to polish before the real thing. Continuity moat:
  the next mock reads the last recap.

### 3.2 "Tailor my application" (draft)

Inputs: the job listing (pasted or Document) + the resume Document. Output:
a rewritten-bullets Note mapping the user's actual history onto this
listing's language, a cover-letter draft, and an honest gap note (which
requirements you genuinely don't meet, and the evergreen advice for each:
address, reframe, or apply anyway). **Hard guardrail, appended by code as
well as prompt: the tool never invents experience, titles, dates, or
credentials** — a qualification the user's data doesn't support becomes a
[BRACKETED PLACEHOLDER], never a fabrication. An assistant that lies on your
resume is a liability sold as a friend. Routes onward to interview prep.

### 3.3 "Check my pay stub" (draft)

Decode-letter's specialist for the document most workers see most often and
read least. Input: the stub Document (or two — "compare to my last one").
Output: a plain-language walkthrough of every line (what OASDI is, where
the 401k match shows up, why net moved), plus **arithmetic checks done by
code, not the model**, over the extracted facts: hours × rate vs. gross,
overtime present when hours exceed 40, rate vs. the previous stub,
deductions that appeared or changed. A mismatch routes (D28) to the wage
claim letter with the numbers attached. Wage theft runs tens of billions a
year, overwhelmingly against hourly workers who were never shown how to
audit a stub — this makes the audit free and automatic. Also the gentlest
on-ramp to §1's granted-data rung: the first stub uploaded to ask a
question becomes the start of the comp timeline.

### 3.4 "Build my raise case" (draft)

The tool the comp timeline and win log exist for. Inputs: optional
"anything not tracked here" free text. Context: win log, the comp timeline
(granted ∪ logged — tenure since the last change is the number most people
can't recall under pressure), current role Note, and the real-terms math
when the public datasets are present ("since your last change, CPI rose 7.1%;
your raise-adjusted pay is down $X in real terms" — computed by code from
owned data + public data, the strongest sentence in the memo). Output: a
raise-case memo Note — accomplishments grouped by what-it-did-for-the-
business, scope added since the last comp change, the tenure and real-terms
math — plus a research checklist naming exactly the market numbers still to
fetch and where (BLS occupational tables, state wage boards, current
postings for your title — the datasets fill these in where they can), placeholders where
they'll slot in. Routes onward to negotiation-prep, which turns the case +
the numbers into the script and the counter-message. If the user's own data
shows the gap, the memo says so plainly — "you should be told you're
underpaid, with hard data you can share" — sourced, not scraped.

### 3.5 "Decode my offer" (draft)

The other comp document with a signature deadline. Input: the offer letter
or contract Document. Output: a total-compensation breakdown (base, bonus
terms as actually written, equity if any — with "what this is worth"
placeholders rather than invented valuations), the benefits translated
(what the 401k match is actually worth per year, what the deductible
means), and the red-flag scan: non-compete, mandatory arbitration,
clawbacks, "other duties as assigned" breadth — each explained neutrally
with the questions to ask before signing. Deadline (offers expire) lands as
an Event. Routes to negotiation-prep ("counter before you sign") and, for
a severance offer, notes the review-window rights and routes to
decode-letter's Rights side. Discovered via decode-letter routing (D28)
as well as the Act zone.

### 3.6 "Find my next move" (chat)

The guidance counselor the 99% never had. A D29 chat whose system prompt
carries `section_context` for **Career + Hobbies + Education** — this is
the cross-referencing dividend: the model sees the warehouse job *and* the
PC-building hobby *and* the finished Learn-something goals, and explores
from there. Behavior contract: asks before telling (what do you like about
the current work, what do you hate, what constraints — money, schedule,
location, body); surfaces adjacent moves the user's own history supports,
including trade/certificate/self-employment paths, not just degree paths;
honest about evergreen tradeoffs (schedule, physicality, licensing) and
placeholder-honest about anything current (specific wages, local demand —
named as things to verify, with the public wage tables slotting in when
present). "Save a recap" lands the exploration Note; the natural exit
routes to Learn-something ("plan the reskilling") — Education's reskilling
line and this tool are two doors into the same room.

### 3.7 "I lost my job" (Situation — plan tool)

Already on PRODUCT.md's candidate-launch list; the widest-blast-radius
career moment and the one where the user is least able to think in
checklists. One plan tool with a rich cross-section brief (the Moving
pattern, M2.4): file for unemployment *this week* (Benefits), the health
insurance fork with its real deadline window (Health + Money — COBRA-vs-
marketplace as a dated Event, placeholders for state specifics), triage the
Money section (which bills flex, which don't — routes to the bill
negotiation and benefits-screener tools), references and story straightening
(what to say about the exit), then the job-search cadence itself as
day-sized tasks. Severance-agreement decoding is already decode-letter's
job; the brief says so (routing, not duplication). Tasks land multi-tagged
across sections and the whole thing reads as one Goal with visible progress
— structure as an antidote to panic.

### 3.8 "Plan my job search" (plan tool)

The calmer sibling of 3.7 for the still-employed: one line ("get out of
retail management", "first dev job") → Goal + day-sized tasks via the
shared breakdown with a search-shaped brief (profile and win log first,
resume second, then a sustainable application cadence with follow-up tasks
baked in — applications tracked as Tasks so the follow-up watcher in §4 has
signal, until email sync makes that automatic). Deliberately boring
machinery; the value is pacing and not dropping threads across weeks.

### 3.9 Workplace rights (the letter family grows — with Rights)

Q2 resolved this placement: work-rights items multi-tag Career + Rights.
Two `Tool::LetterBase` additions (~a prompt each, per TOOLS_PLAN):
**wage claim** (unpaid hours/overtime/final paycheck: demand letter from
the user's own stub-extracted or logged dates and amounts, state-agency
escalation named as a placeholder, paper-trail follow-up tasks) and
**accommodation request** (ADA/pregnancy/religious: the formal
interactive-process letter). Decode-letter learns to route employer mail
to them; the stub check (3.3) routes here with numbers attached.
Misclassification (1099-vs-employee) starts as an explainer section inside
wage claim rather than its own tool — promote it when demand shows.

### 3.10 Small-business-in-a-box (named, deferred)

PRODUCT.md's self-employment suite (invoicing, bookkeeping categorization,
customer replies, marketing copy) is real and mission-core — a plumber
capturing the AI windfall themselves — but it is its own deep-dive with its
own primitives conversation (invoices and customers strain the six-primitive
model). Until then, the hobby→side-gig ramp gets its first step here: a
**"First paying customer"** plan tool (price it, a simple invoice template
Note, where your first three customers hide, the record-keeping habit) is
cheap on existing infra and serves the widest self-employment moment. The
full suite stays parked in PRODUCT.md until someone asks for the deep-dive.

## 4. Agent (D20 watchers — deterministic over owned data, suggestions table only)

The comp timeline (granted ∪ logged) is what makes this slate strong:
every nudge below is arithmetic over sourced facts, never inference.

- **Raise cadence** — the checkup-cadence twin and the section's flagship
  nudge: latest comp-timeline entry ≥ N months ago (default 12, sensible
  dial later) and none upcoming → "It's been 14 months since your last comp
  change — build your case?"; accept opens Build-my-raise-case. No timeline
  at all → one-time gentler variant inviting the first rung ("upload a pay
  stub or log your last raise and I'll keep watch"). Yearly fingerprint
  buckets (the checkup convention).
- **Real-terms drift** — the quiet pay cut, caught: comp timeline flat
  while the on-file CPI series rose past a threshold → "your pay has lost
  ~6% of its buying power since your last change" with the arithmetic
  shown; accept opens the raise case with the math pre-loaded. Pure code
  over owned data + a public dataset; no LLM, no web at nudge time. This
  is the watcher version of "squeeze employers for the maximum value of
  your time" — and it fires for exactly the people who never think to
  check.
- **Stub anomaly** — a newly-analyzed stub's extracted facts fail the 3.3
  checks (rate dropped, hours × rate ≠ gross, overtime vanished, new
  deduction) → suggestion routing to Check-my-pay-stub with both stubs
  attached. Deterministic arithmetic over extraction output; per-stub
  fingerprint.
- **Interview ahead** — upcoming Career-tagged Event whose title says
  interview, with no interview-prep run since it was created → "Interview
  Thursday — want to prep?"; accept opens the prep tool. Pure SQL over
  events ∪ tool_runs; per-event fingerprint so it fires once.
- **Application follow-up** — open application Task (created by 3.8's plan,
  by hand, or — once the D26 email consumer lands — auto-logged from
  confirmation emails) untouched for 10+ days → "Still waiting on Acme —
  nudge them?" Reuses the stale-task shape with a shorter window and a
  Career filter; cap concurrent nudges like stale-task does.
- **Cert renewal** — already covered by renewal radar; the §1 capture just
  has to put expirations on the calendar. Zero work, name it in the UI.
- **Win-log keeper** — a comp timeline exists (user has a job) but no win
  Note in 8+ weeks → one quiet "log a win while it's fresh". The habit is
  the asset; this guards it. Quarterly fingerprints, Quiet-dial only —
  this one must never nag.
- **Job scout / market-rate radar** *(built — see §5)*.

## 5. The external-data layer (built — D-public-datasets/D-career-web)

The three headline asks — watch job boards for me, tell me what my role
pays elsewhere, apply on my behalf — resolved into two decisions and are
built:

- **Market-rate data is local public data (D-public-datasets).** A two-layer dataset
  store (`storage/datasets/` from `RefreshDatasetsJob` or `/admin`'s
  air-gapped file import, over `db/datasets/` seeds) serves BLS numbers
  with the vintage always displayed. The CPI-U annual series ships seeded;
  the OES/OEWS national wage table arrives by fetch or import (never
  bundled unverifiable). The raise case cites the on-file CPI drift and
  closest-median rows as sourced reference points; the **real-terms-drift
  watcher** turns a flat comp timeline × risen CPI into "your pay lost ~6%
  of its buying power" — arithmetic, no LLM, no web at nudge time. Absent
  data degrades to the placeholder behavior, never to a guess.
- **The web arrives on three leashes (D-career-web).** `Web::Fetch` is the
  app-side floor — deterministic, SSRF-guarded, size-capped fetch of one
  user-supplied URL — behind the paste-a-listing-link inputs on interview
  prep and the application tailor, identical on frontier APIs and local
  models. `model_profiles.web_capable` is the declared model-side rung:
  an admin checkbox for genuinely-browsing providers that relaxes
  never-assert-current-facts into look-it-up-and-cite. The **job scout**
  rides both: per-user `job_feeds` (RSS/Atom, Greenhouse/Lever boards,
  USAJobs — feeds and open APIs only, nothing ToS-fraught) are scanned on
  the agent cadence, one model call ranks fresh postings against the
  Career + Hobbies + Education record, and survivors land as suggestions
  only — one per posting ever, accept opens Tailor-my-application
  prefilled. First sanctioned exception to SQL-only watchers; zero
  exception to the D20 write surface.
- **Auto-apply is ask-then-send, email only (D-career-web).** The compose panel on
  a Tailor-my-application run is the review: the user's own linked
  mailbox, their edits to every word, one explicit click — and the sent
  application lands on the record as an Applied Event plus a follow-up
  task. No ATS form automation (the robo-apply arms race is *hurting*
  applicants), and nothing the app initiates ever sends. If that ceiling
  moves again it moves by explicit user-visible configuration (D9), not
  by inches.

## 6. Cross-section dividends

- **× Money** — a raise won is Budget's biggest single input; the comp
  timeline is half of cash-flow's income side (and Money's future
  transactions layer feeds it back, §1); lost-my-job triages bills and
  routes to the benefits screener; wage claims are money recovered. The
  section pays for itself in Money's terms.
- **× Education** — reskilling is one room with two doors (Find-my-next-move
  ↔ Learn-something); the tutor already drills any cert exam; finished
  learning Goals are resume lines the tailor tool can actually cite.
- **× Hobbies** — the hobby→side-gig ramp (Show-&-tell writeups are half a
  portfolio; First-paying-customer is the bridge); hobby context is what
  makes job-scout matching *enjoyment*-aware rather than title-matching.
- **× People** — references, former coworkers, the recruiter who emailed
  once: stay-in-touch already nudges; Reconnect prefilled with "ask if
  they'd be a reference" is a strictly better Reconnect.
- **× Rights** — the Q2 overlap, now with teeth: wage claim fed by stub
  arithmetic, accommodation letters, decode-letter routing employer mail,
  severance and offer review at the worst and best moments.
- **× Health** — lost-my-job's insurance fork; burnout showing up in the
  balance insight; accommodation requests bridge both.

## 7. Build order

1. ✅ **Foundation (D-career-signal)** — Career page capture ("Tell me about your work"
   + the win-log quick capture + "log a comp change"), plus **pay-stub-aware
   document analysis** feeding the comp timeline (extraction + auto-Event
   with provenance); renewal radar and negotiation-prep get better for
   free, and the LinkedIn-export importer bootstraps the profile.
2. ✅ **Interview prep + mock interview** — the asked-for pair; zero new
   infra (draft + D29 chat + D28 routing; the `:textarea` input kind is the
   one DSL addition).
3. ✅ **Check my pay stub** — rides step 1's extraction; the
   `Career::PayStubAudit` arithmetic, the stub-anomaly watcher, and the
   wage-claim letter it routes to.
4. ✅ **Tailor my application** — completes the application chain
   (tailor → prep → mock → negotiation-prep).
5. ✅ **Build-my-raise-case + Decode-my-offer + raise-cadence watcher** —
   the comp timeline pays out; the section's proactive flagship.
6. ✅ **"I lost my job" Situation + Plan-my-job-search** — the safety net
   and the cadence machine, plus the application-follow-up and
   interview-ahead watchers riding their conventions.
7. ✅ **Find-my-next-move chat** + accommodation request + decode-letter
   routing (employer mail now routes to decode_offer and wage_claim).
8. ✅ **The external-data layer (D-public-datasets/D-career-web)** — the dataset tier (CPI seed,
   OES fetch/import, admin card, real-terms-drift watcher, raise-case
   integration), the web floor (`Web::Fetch` + listing-URL inputs +
   `web_capable` flag), the job scout (`job_feeds` + parsers + the ranking
   watcher), and ask-then-send email applications.
