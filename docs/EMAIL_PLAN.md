# EMAIL_PLAN.md

Design for **email import & monitoring**: connect a mailbox (Gmail, Zoho, iCloud,
Fastmail, self-hosted — anything IMAP), let the assistant query it, digest it daily,
raise an alarm for genuinely urgent mail, and nudge when a sent message has gone a week
without a reply ("boomerang"). This is the email consumer that D26 left pending and the
richest linked-account surface so far.

It is also the **template for every high-volume source after it** — bank transactions,
chat exports, browser history, whatever we pull in next. The architectural centerpiece
here (the *mirror layer*, D30) is designed once and reused; email is just the proving
source.

Proposed decisions are logged as **D30–D31** in `DECISIONS.md` (provisional until the
build passes prove them, the D18–D20 convention). Open questions raised: Q14–Q15.

---

## 1. The four user stories

1. **Query** — "When did the landlord say the inspection was?" Search and ask questions
   over your own mail, in the app.
2. **Daily digest** — one calm summary of the new mail that actually matters, on the
   Dashboard and (optionally) pushed through your notification channels.
3. **Urgent alert** — a truly time-sensitive email (court date moved, flight cancelled,
   "respond by Friday") pings your phone *now*, not at tomorrow's digest.
4. **Boomerang** — you emailed someone a week ago and never heard back; the assistant
   suggests following up and drafts the nudge.

Everything above must degrade gracefully with **no model configured** (the
value-without-AI principle): sync, browse, search, and boomerang are deterministic;
triage, digest phrasing, and question-answering are the AI garnish.

---

## 2. How email fits the architecture: the mirror layer (D30)

### The problem with treating email like contacts/calendar

The two existing sync consumers (CardDAV → People, CalDAV → Events) **import**: every
synced record becomes a primitive, because every contact and appointment *is* a life
item the user would have entered by hand. Email is different in kind:

- **Volume**: thousands of messages, arriving forever. Ten thousand Notes would bury
  the primitive pool and make every cross-cutting view worse.
- **Relevance**: most mail is noise. A primitive is something the user owns and tends;
  a newsletter is not.
- **Sensitivity**: a mailbox is the most sensitive data the app will ever hold —
  password resets, medical results, other people's words.

### The rule

> **High-volume external streams are *mirrored*, not imported.** A mirror is a
> per-source cache table, owned by one user, outside the primitive pool, outside the
> sharing model. Mirror rows become primitives only by **promotion** — an explicit user
> click, or an accepted suggestion (D20). Low-volume identity-shaped data (contacts,
> calendars) keeps importing directly, as today.

What this buys us, in existing-architecture terms:

- **The lens model stays clean (D5).** Sections remain lenses over primitives; email is
  not a section and never owns one. Promoted items are ordinary primitives — tagged,
  shared, visible in Calendar/Today/Dashboard like everything else. A promoted
  attachment is an ordinary Document, which means `AnalyzeDocumentJob` and the
  decode-letter front door (D28) work on mail for free.
- **Privacy is structural (D9).** Mirror tables don't include `Visible` or
  `Sectionable`; there is no `visible_to` path to them, so no grant can ever expose a
  mailbox and the agent structurally cannot read another member's mail. The only read
  path is `user.email_messages`. Sharing happens at promotion, where normal grants
  apply to the promoted primitive.
- **Per-source tables, deliberately boring.** No generic polymorphic `synced_items`
  table — email gets real columns for real queries (the same lesson as the six
  primitives). The *pattern* is reused for the next source; the table is not.
- **Export/admin conventions carry over**: mirror rows join the D14 per-user export
  (they're the user's own data); `/admin` sees sync status and counts, never contents
  (D23/D9).

---

## 3. Connection layer: rides D26/D27, nothing new

The `email` provider already exists in `LinkedAccount::PROVIDERS` (host / username /
password, scopes `read_inbox` / `read_archive` / `send`). Changes are additive:

- **`sync_service: "Email::ImapSync"`** on the registry entry, so the existing
  `SyncLinkedAccountJob` dispatch, `synced_at`/`sync_error` fields, and Settings-card
  sync UI all just work.
- **Provider presets in the form UI**: chips for Gmail / Zoho / iCloud / Fastmail /
  Outlook that prefill the host and link the provider's app-password page. One generic
  IMAP provider underneath — presets are copy, not registry entries.
- **Capability honesty per host**: Gmail (2FA + app password), Zoho (`imap.zoho.com`,
  app password), iCloud, Fastmail, and self-hosted servers work today.
  **Outlook/Microsoft does not** — Microsoft has retired basic IMAP auth, so the
  Outlook chip says "needs Sign-in with Microsoft — coming with OAuth (D27)" instead of
  pretending. One-click Gmail OAuth (XOAUTH2) also arrives with the D27 relay, on the
  timeline D27 already set (restricted-scope CASA review; app passwords cover Gmail
  meanwhile).
- **Scopes get real consumers**: `read_inbox` gates sync entirely (checked via
  `allows?` inside the service, fail-closed); `read_archive` gates backfill beyond the
  default window; `send` gates nothing yet — v1 **never sends mail** (see §8 and Q15).
- **Prerequisite: encrypt `linked_accounts.credentials`.** The pending D26 follow-up
  stops being deferrable the moment mailbox passwords flow through at volume. The M4
  AR-encryption setup (per-instance keys in `storage/`) already exists; this is
  `encrypts :credentials` + a backfill migration, done first, in wave 1.

---

## 4. Schema

Two tables plus a promotion join (all per-user, no `Visible`/`Sectionable`):

**`email_folders`** — sync bookkeeping, one row per tracked IMAP folder per link:
`linked_account` FK, `user` FK, `name` (server-side name), `role`
(`inbox`/`sent`/`other`), `uidvalidity`, `last_seen_uid`, timestamps. Incremental sync
state lives here; a UIDVALIDITY change resets `last_seen_uid` and re-mirrors the
window. v1 tracks Inbox + Sent (Sent is what makes boomerang possible), discovered via
RFC 6154 SPECIAL-USE attributes with common-name fallbacks.

**`email_messages`** — the mirror:
- Identity: `user` FK, `linked_account` FK, `email_folder` FK, `uid`, `message_id`
  (RFC 5322, unique per link — the dedupe key), `thread_key` (root of the
  References/In-Reply-To chain, falling back to `message_id`; indexed — threads are a
  derived grouping, not a table).
- Envelope: `direction` (`inbound`/`outbound`, derived from sender vs. the link's own
  address), `from_email`, `from_name`, `to_emails` (JSON), `cc_emails` (JSON),
  `subject`, `sent_at`.
- Content: `snippet` (first ~200 chars, for lists), `body_text` (plain text — HTML
  stripped on ingest, truncated ~20k chars), `attachments` (JSON metadata:
  filename/mime/size — **bytes are not stored**; fetched from the server on promotion
  only), `bulk` (boolean — List-Unsubscribe / Precedence / noreply heuristics, computed
  at ingest; feeds triage and boomerang).
- State: `seen` / `answered` flags (from IMAP, refreshed on sync), `triage` (JSON,
  §6), `importance` (integer 0–3, denormalized from triage for cheap queries),
  `triaged_at`.

**`email_message_items`** — promotion provenance, mirroring `tool_run_items`:
`email_message` FK + polymorphic `item`. The message page shows what a message became;
deleting the message never touches the primitive.

Retention: the mirror is a window, not an archive (the mailbox itself remains the
archive of record). Default 90 days back for Inbox + Sent; a nightly prune deletes
mirror rows that fell out of the window *unless promoted or referenced by a live
suggestion*. Exact knobs are Q14.

---

## 5. Sync engine: `Email::ImapSync`

Same shape as `People::CarddavSync` — a plain-Ruby service, one client class, no vendor
gem:

- **`Email::ImapClient`** wraps `net-imap` (bundled gem, add to Gemfile) the way
  `Dav::Client` wraps Net::HTTP: connect/TLS, login, folder discovery, `UID SEARCH` /
  `UID FETCH`, friendly `Email::ImapClient::Error`s. XOAUTH2 support lands here later
  with D27 — one authenticator, no resync.
- **Parsing** uses the `mail` gem Rails already ships (ActionMailer dependency):
  headers, MIME tree walk for the best text part, HTML→text fallback, attachment
  metadata.
- **Incremental algorithm**, per folder: first run backfills the window (90 days) in
  batches; every run after fetches UIDs > `last_seen_uid`, refreshes flags on recent
  known messages (cheap `UID FETCH ... (FLAGS)` sweep so `seen`/`answered` stay
  truthful), advances the cursor. Dedupe by `message_id` per link, so re-linking or
  UIDVALIDITY resets never duplicate.
- **Scope gate inside the service** (`allows?("read_inbox")` or bail), the D26 rule.
- **Recurring background sync** — the generic piece D26 left pending, built here for
  all syncable providers at once: registry entries gain `sync_every:` (email 15m, DAV
  hourly), and one Solid Queue recurring task fans out `SyncLinkedAccountJob` for links
  whose `synced_at` is stale. Manual "Sync now" stays.
- After each sync with new mail: enqueue `Email::TriageJob` (§6) and the urgent-alert
  check (§7). Sync itself stays model-free.

---

## 6. Triage: AI labels on the mirror, never primitives

`Email::TriageJob` (rides `RetriesModelCalls`) classifies new messages in batches of
~20 per LLM call — skipped entirely when no model is configured, silent-on-failure with
`AppError` recording (D23/D24). Obvious bulk mail (`bulk: true`) is pre-labeled by code
and never spends a token.

Per message, the JSON contract returns: `category`
(`action_needed` / `time_sensitive` / `fyi` / `receipt` / `newsletter` / `noise`),
`importance` 0–3, optional `deadline_on` + `deadline_title` when the text states one,
and a one-line `why`. Stored in `email_messages.triage`; `importance` denormalized.

Trust-ladder discipline (D20): triage **only writes labels on the mirror**. It never
creates a Task, files a Note, or touches primitives. Labels power the mail page's
filters, the digest's selection, the urgent path, and *suggestions* — a stated deadline
becomes a pending suggestion ("Add 'Appeal deadline — May 3' to your calendar?") whose
accept materializes the Event, exactly like every other watcher-born suggestion.

---

## 7. Surfaces

### `/mail` — the browser (zero-AI value)

A lightweight owner-only mail view, deliberately not a mail client: message list
grouped by thread (newest first), triage filter chips (Needs action / Time-sensitive /
Everything), sender/subject/body search (SQL `LIKE` first; FTS5 in wave 5), and a
message page showing the text body, attachment list, and the **promotion row**:

> **→ Task** · **→ Event** · **→ Note** · **attachment → Document** · **Decode this**

Promotion pre-fills from the message (task title from subject, event date from triage's
deadline, document from the fetched attachment), files nothing automatically (D16's
categorize jobs run on the new primitive as usual), records provenance in
`email_message_items`, and the promoted item is thereafter an ordinary primitive.
"Decode this" is promotion-to-Document + the existing D28 decode entry point — scary
mail gets the same front door as scary paper.

Navigation: `/mail` hangs off the sidebar next to the Documents vault (a source
browser, not a section), shown only when an email link exists.

### Daily digest

Deterministic selection, LLM phrasing, in-app body — the `Users::WeeklyDigest` recipe:

- A daily job (same recurring slot as the daily `AgentScanJob` cadence) collects new
  messages since the last digest with `importance >= 2`, plus counts by category.
- One LLM call phrases 2–4 warm sentences (facts in, prose out, silent failure —
  deterministic list renders regardless).
- Lands as a **Mail card on the Dashboard** (stored on the link, e.g.
  `linked_accounts.digest` JSON) listing the selected messages with links into `/mail`.
- If the user turned digest notifications on, `NotifyJob` sends the pointer through the
  existing channels — **counts and titles only, never bodies** (D22 holds; a lock
  screen is not private).

### Urgent alerts — "text me if it's serious"

The immediate path, checked right after triage (not batched to the digest):
`importance == 3 && category == time_sensitive` → `NotifyJob` *now*, through the same
D22 channels — which is exactly how "send a text" stays mission-true: a webhook to ntfy
(or a user's Twilio hook) reaches a phone without us running an SMS service. Guardrails:
off by default, hard cap (3/day), one alert per thread, titles-only payload
("Time-sensitive email from Alameda Superior Court").

**Dials live on the source, not on sections** (part of D31): email isn't a section, so
`user_sections.agent_level` can't govern it. The Settings email card gets its own
visible dials — digest **on/off**, alerts **off/on** — the same
user-controlled-configuration posture as the D26 scope toggles.

### Boomerang — `Watcher::EmailNoReply`

A deterministic watcher, the D20 ideal — pure SQL over the mirror, no model calls:

> outbound message, 7+ days old, latest outbound in its thread, no inbound message in
> the thread after it, recipient not `bulk`/noreply → suggestion.

"You emailed Dana about 'deposit return' 9 days ago and haven't heard back." Fingerprint
per thread (dismissed = gone for good, the standard convention); at most 3 live nudges
(the stale-task cap); sectionless (runs at the Quiet weekly default), suggestions filed
under People. Accept opens the one new tool this plan adds — **`email_follow_up`**
(draft, People + Career): reads the thread from the mirror, drafts a short, polite nudge
as a Note plus a "send the follow-up" Task. The user copies it into their mail client —
the app **never sends** (§8).

### Ask your email — `ask_your_email` (wave 5)

A Tier-A-honest question tool (draft kind) until the adapter grows real tool-calling:

1. `question` input → one LLM call turns it into search terms + filters (sender/date
   range), JSON out.
2. Code runs the search against the mirror (FTS5 virtual table over
   subject/body_text, added this wave — plain SQL fallback where FTS5 is unavailable).
3. Second call answers over the top-N hits **with citations** (sender + date per
   claim), instructed to say "nothing in your synced mail matches" rather than guess —
   the mirror is a 90-day window, not the whole mailbox, and the answer must say so
   when it matters.

Renders on the run page (like decode), with "Save as note" and `next_tools`-style
promotion offers for any dates it found. When a `capabilities` flag lands (Q9), this
upgrades to a chat-kind tool with real per-turn retrieval.

---

## 8. What we deliberately do not build

- **Sending mail.** The `send` scope stays dormant. Every output is a draft the user
  copies — the D19 line ("the app never sends anything on the user's behalf") holds
  until sending gets its own consent design (**Q15**).
- **Attachment byte storage.** Metadata only; bytes enter the app solely by promotion
  to a Document, where Active Storage already owns the problem.
- **A full mail client.** No compose, no folders UI, no mark-as-read pushed back to the
  server (v1 sync is read-only against the mailbox). The user's mail app remains their
  mail app; ours is the *assistant's* view of it.
- **Webhooks/push from providers (Gmail Pub/Sub etc.).** Polling every 15 minutes is
  self-host-friendly and provider-agnostic; push channels are provider-specific
  landlord surface area for marginal latency.

---

## 9. Build sequence

Each wave ends green (`bin/rails test`, `bin/rubocop`) with `docs/STATUS.md` updated.

1. **E1 — Mirror + sync (the foundation).** `encrypts :credentials` + backfill;
   `email_folders` / `email_messages` / `email_message_items` migrations;
   `Email::ImapClient` + `Email::ImapSync` (Inbox+Sent, incremental, dedupe, window
   backfill); registry wiring + provider preset chips; recurring background sync
   fan-out (`sync_every:`, all syncable providers); `/mail` list + message page +
   promotion row. *Fully useful with no model.*
2. **E2 — Triage.** `Email::TriageJob` (batched, bulk-precheck, D24 retries), triage
   filters on `/mail`, deadline suggestions through the suggestions table.
3. **E3 — Reach.** Daily digest (Dashboard Mail card + D22 pointer notification) and
   urgent alerts (immediate, capped, off by default); the source-level dials on the
   Settings email card.
4. **E4 — Boomerang.** `Watcher::EmailNoReply` + the `email_follow_up` draft tool.
5. **E5 — Ask your email.** FTS5 index + the two-call `ask_your_email` tool.

Parked, with owners elsewhere: OAuth/XOAUTH2 + Outlook + one-click Gmail (D27 relay
work, unchanged by this plan); sending (Q15); the next mirrored source (bank
transactions is the likely candidate — it reuses D30 wholesale: mirror table, promotion,
triage labels, source dials).

### Testing conventions

The established patterns apply: a fake IMAP client (fixture RFC822 messages) under the
sync tests, the WebMock-stubbed endpoint under triage/digest/tool tests
(`tool_run_job_test.rb` pattern), watcher tests as pure fixture SQL
(`stale_task` pattern: thresholds, caps, fingerprints, bulk exclusion), and structural
guards asserted in code: no `Visible`/`Sectionable` on mirror models, promotion-only
writes, titles-never-bodies payloads, the 3/day alert cap.

---

## 10. Decisions proposed (for DECISIONS.md)

- **D30. High-volume external streams are mirrored, not imported.** Per-source mirror
  tables (owner-private, no `Visible`/`Sectionable`, no grants, windowed retention);
  primitives are created only by explicit promotion or accepted suggestions, with
  provenance recorded. Contacts/calendar keep importing (low-volume, identity-shaped).
  Email proves the pattern; future sources reuse it.
- **D31. Email monitoring rides the existing agent rails, with dials on the source.**
  Triage writes labels on the mirror only; the digest is deterministic selection +
  LLM phrasing landing in-app with D22 pointer notifications; urgent alerts are the
  one immediate path (capped, off by default); boomerang is a deterministic watcher
  over the Sent mirror; nothing is ever sent on the user's behalf. Because email is a
  source rather than a section, its agent dials live on the linked-account Settings
  card, not on `user_sections`.

Open questions raised:

- **Q14 — mirror retention.** 90-day window and nightly prune are guesses; promoted or
  suggestion-referenced rows are kept, but should the user be able to widen the window
  ("mirror everything"), and does the mirror join the D14 export as-is?
- **Q15 — sending mail.** The `send` scope exists and boomerang makes it tempting
  ("just send the follow-up"). Sending is the first time the app would *act on the
  world* for the user — it needs its own consent design (per-message confirm? a
  sent-by-assistant audit trail?) and is explicitly out of scope until then.
