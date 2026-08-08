# CAREER.md

Section deep-dive for **Career** — design for how the section earns its place
across all three modes (D6). Everything here rides existing infrastructure
(D17 breakdown, D19 tools, D20 watchers, D28 routing, D29 chat) except where
explicitly flagged. The one new decision it needs — how career signal gets
into the app — is **D30** in `DECISIONS.md`; the external-data questions it
raises are **Q14–Q15**.

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

## 1. Knowing the user's work life (the foundation — D30)

Everything else needs to know: what the user does, what they're paid, what
they've accomplished, and when compensation last moved. The Hobbies answer
(profile = ordinary primitives under the lens, no schema) works here too,
with one addition — two deliberately-manual logging conventions that become
the substrate for the proactive layer:

- **Comp-change Events.** A raise, a promotion, a job change, an annual
  review: logged as a Career-tagged all-day Event ("Raise: $19 → $21/hr").
  This is the Q8 lesson applied to Career — the app can't see your paycheck
  and shouldn't pretend to; a one-tap logged fact beats an inferred guess,
  and *no signal means no nudge*. The raise-cadence watcher (§4) reads only
  these.
- **The win log.** Quick-capture Career-tagged Notes: "caught the inventory
  error before the audit", "covered the closing shift six weeks straight",
  "shipped the migration". Day-one capture cost: one line (D16 — the
  categorizer files it). Payoff: the raise case and every resume tailor and
  interview prep *builds itself* from receipts, instead of the user trying
  to remember two years of work the night before a review. This habit is the
  section's whole game — the Career page leads with it the way Hobbies leads
  with "What do you do for fun?".
- **The rest is ordinary primitives**: resume/CV in the vault (Document),
  a work-history/skills/current-comp Note ("Tell me about your work" — the
  same interview-capture pattern as the hobby profile), certifications and
  licenses as Events with expiry dates (renewal radar already watches those
  for free), applications and interviews as Tasks/Events as they happen.

Tools read all of this through the existing `section_context` — the
negotiation-prep tool already does, so a user with a win log gets a better
prep sheet *today*, before anything below is built.

## 2. Organize (mostly already built — name it, don't build it)

The lens dividend again — Career-Organize fell out of Milestone 1:

| Life thing | Primitive |
|---|---|
| Resume, offer letters, reviews, pay stubs, contracts | Documents |
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
  vault Document; a URL is Q15's first slice, see §5 — plus optional
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

### 3.3 "Build my raise case" (draft)

The tool the win log exists for. Inputs: optional "anything not tracked
here" free text. Context: win log, comp-change Events (tenure since the
last change — the number most people can't recall under pressure), current
role Note. Output: a raise-case memo Note — accomplishments grouped by
what-it-did-for-the-business, scope added since the last comp change, the
tenure math — plus a research checklist naming exactly the market numbers to
fetch and where (state wage boards, BLS occupational data, current postings
for your title — see Q14), placeholders where they'll slot in. Routes
onward to negotiation-prep, which turns the case + the fetched numbers into
the script and the counter-message. If the user's own data shows the gap
("no comp change logged in 26 months"), the memo says so plainly — that's
owned hard data, and it's exactly the "you should be told you're underpaid"
moment done honestly at Tier A.

### 3.4 "Find my next move" (chat)

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
named as things to verify, per Q14). "Save a recap" lands the exploration
Note; the natural exit routes to Learn-something ("plan the reskilling") —
Education's reskilling line and this tool are two doors into the same room.

### 3.5 "I lost my job" (Situation — plan tool)

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

### 3.6 "Plan my job search" (plan tool)

The calmer sibling of 3.5 for the still-employed: one line ("get out of
retail management", "first dev job") → Goal + day-sized tasks via the
shared breakdown with a search-shaped brief (profile and win log first,
resume second, then a sustainable application cadence with follow-up tasks
baked in — applications tracked as Tasks so the follow-up watcher in §4 has
signal). Deliberately boring machinery; the value is pacing and not
dropping threads across weeks.

### 3.7 Workplace rights (the letter family grows — with Rights)

Q2 resolved this placement: work-rights items multi-tag Career + Rights.
Two `Tool::LetterBase` additions (~a prompt each, per TOOLS_PLAN):
**wage claim** (unpaid hours/overtime/final paycheck: demand letter from
the user's own logged dates and amounts, state-agency escalation named as a
placeholder, paper-trail follow-up tasks) and **accommodation request**
(ADA/pregnancy/religious: the formal interactive-process letter). Decode-
letter learns to route employer mail to them. Misclassification (1099-vs-
employee) starts as an explainer section inside wage claim rather than its
own tool — promote it when demand shows.

### 3.8 Small-business-in-a-box (named, deferred)

PRODUCT.md's self-employment suite (invoicing, bookkeeping categorization,
customer replies, marketing copy) is real and mission-core — a plumber
capturing the AI windfall themselves — but it is its own deep-dive with its
own primitives conversation (invoices and customers strain the six-primitive
model). Until then, the hobby→side-gig ramp gets its first step here: a
**"First paying customer"** plan tool (price it, a simple invoice template
Note, where your first three customers hide, the record-keeping habit) is
cheap on existing infra and serves the widest self-employment moment. The
full suite stays parked in PRODUCT.md until someone asks for the deep-dive.

## 4. Agent (D20 watchers — deterministic SQL, suggestions table only)

- **Raise cadence** — the checkup-cadence twin and the section's flagship
  nudge: latest comp-change Event ≥ N months ago (default 12, sensible dial
  later) and none upcoming → "It's been 14 months since your last comp
  change — build your case?"; accept opens Build-my-raise-case. No comp
  Events logged ever → one-time gentler variant inviting the logging habit
  ("Tell me when your pay last changed and I'll keep watch"). Yearly
  fingerprint buckets (the checkup convention). This delivers the "track
  when you last asked" promise with zero web dependency.
- **Interview ahead** — upcoming Career-tagged Event whose title says
  interview, with no interview-prep run since it was created → "Interview
  Thursday — want to prep?"; accept opens the prep tool. Pure SQL over
  events ∪ tool_runs; per-event fingerprint so it fires once.
- **Application follow-up** — open application Task (created by 3.6's plan
  or by hand) untouched for 10+ days → "Still waiting on Acme — nudge them?"
  Reuses the stale-task shape with a shorter window and a Career filter;
  cap concurrent nudges like stale-task does.
- **Cert renewal** — already covered by renewal radar; the §1 capture just
  has to put expirations on the calendar. Zero work, name it in the UI.
- **Win-log keeper** — comp Events exist (user has a job) but no win Note
  in 8+ weeks → one quiet "log a win while it's fresh". The habit is the
  asset; this guards it. Quarterly fingerprints, Quiet-dial only — this one
  must never nag.
- **Job scout / market-rate radar** *(Tier B, deferred — see §5 and Q15)*.

## 5. The external-data horizon (honest Tier answers)

The three headline asks — watch job boards for me, tell me what my role
pays elsewhere, apply on my behalf — are the section's endgame and all three
need data the app doesn't own. The Q9 discipline (no capability lies) forces
the split; it doesn't force deferral of everything:

- **Market-rate data has a middle tier (Q14).** Between Tier A and the live
  web sits **published public data**: BLS OES wage tables (occupation ×
  metro, public domain, flat files) and state equivalents. An instance
  could fetch a dataset periodically and serve every raise case and
  career-explorer chat from *owned local data* — no scraping, no ToS
  exposure, and frankly a stronger artifact for the boss conversation than
  a Glassdoor screenshot ("BLS says the metro median for my title is $X"
  survives scrutiny). Non-US coverage and staleness honesty are the open
  questions; until Q14 resolves, the tools name the sources and the user
  fetches the number (the negotiation-prep placeholder pattern, already
  shipped).
- **The job scout waits on Q9 but its shape is decided now (Q15).** When
  live-web capability lands: a scheduled scan reads the profile + Hobbies +
  Education context, searches configured boards, and writes **suggestions
  only** — "this posting fits the PC-building hobby and the A+ cert plan,
  want the application kit?" — accept opens Tailor-my-application prefilled.
  The D20 write-surface discipline (suggestions table, propose-don't-
  dispose) survives contact with the web even though SQL-only purity
  doesn't; that's the line Q15 is about. Its narrowest first slice is also
  the interview-prep URL paste: fetching *one user-supplied URL at run
  time* is a far smaller capability than agentic search, and probably
  Q9's cheapest proving ground.
- **Auto-apply stays capped at prepare-everything, send-nothing.** The
  ceiling is deliberate, not timid: "all output is draft output" is a
  load-bearing trust rule (D20), an application sent in your name is an
  outward-facing act with real reputational cost, and the robo-apply arms
  race is *hurting* applicants (ATS filters now discard what looks
  automated). The owned-context edge is making each application visibly
  better and one click from sent — scout finds it, kit tailors it, task
  schedules it, the user hits send. If that ceiling ever moves, it moves by
  explicit user-visible configuration (D9), not by inches.

## 6. Cross-section dividends

- **× Money** — a raise won is Budget's biggest single input; lost-my-job
  triages bills and routes to the benefits screener; wage claims are money
  recovered. The section pays for itself in Money's terms.
- **× Education** — reskilling is one room with two doors (Find-my-next-move
  ↔ Learn-something); the tutor already drills any cert exam; finished
  learning Goals are resume lines the tailor tool can actually cite.
- **× Hobbies** — the hobby→side-gig ramp (Show-&-tell writeups are half a
  portfolio; First-paying-customer is the bridge); hobby context is what
  makes job-scout matching *enjoyment*-aware rather than title-matching.
- **× People** — references, former coworkers, the recruiter who emailed
  once: stay-in-touch already nudges; Reconnect prefilled with "ask if
  they'd be a reference" is a strictly better Reconnect.
- **× Rights** — the Q2 overlap, now with teeth: wage claim and
  accommodation letters, decode-letter routing employer mail, severance
  review at the worst moment.
- **× Health** — lost-my-job's insurance fork; burnout showing up in the
  balance insight; accommodation requests bridge both.

## 7. Build order

1. **Foundation (D30)** — Career page capture ("Tell me about your work" +
   the win-log quick capture + "log a comp change"), conventions documented
   in-UI; renewal radar and negotiation-prep get better for free.
2. **Interview prep + mock interview** — the asked-for pair; zero new
   infra (draft + D29 chat + D28 routing).
3. **Tailor my application** — completes the application chain
   (tailor → prep → mock → negotiation-prep).
4. **Build-my-raise-case + raise-cadence watcher** — the win log pays out;
   the section's proactive flagship.
5. **"I lost my job" Situation + Plan-my-job-search** — the safety net and
   the cadence machine (plus the application-follow-up and interview-ahead
   watchers riding their conventions).
6. **Find-my-next-move chat** — the counselor; richest cross-section read.
7. **Letter-family additions** (wage claim, accommodation request) +
   decode-letter routing.
8. **Q14 dataset tier**, then **Q15 scout/URL-fetch** when Q9 resolves —
   the Tier-B unlocks, upgrading raise-case and the scout in place.
