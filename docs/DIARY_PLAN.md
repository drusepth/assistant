# DIARY_PLAN.md

Build plan for the **diary**: a private journal under the Vault sidebar group, so a
household member's most personal writing lives on the box they own instead of in a
notes app that syncs to someone else's cloud — sealed with the same envelope
encryption the password vault proved out. **Status: planned** — this document is the
design record; waves land per §9.

Decisions here are logged as **D-diary-vault** and **D-vault-sealed** in
`DECISIONS.md`. Open questions are logged as **Q-diary-ai** and
**Q-diary-attachments**.

---

## 1. What we're building and why

A diary is the most concentrated form of the thing this app exists to hold: the
durable memory asset. It is also the data with the strongest possible privacy
expectation — stronger than passwords, in one sense, because a password protects an
account while a diary *is* the person. Corporate journals (Day One, Apple Journal,
Notion) rent that custody; a plain Note in this app protects it at the AR-encryption
tier, where the keys sit in `storage/` next to the database and any backup holder or
household admin can read every word. The password vault (PASSWORDS_PLAN.md) built
the answer — envelope encryption keyed off the login password, so **at rest, the
server cannot read it** — and a diary is the second thing in a household that
deserves that answer.

The bar we're aiming at:

- **A writing surface worth returning to** — a focused editor, one entry per day by
  default (backfillable), autosave, a calendar/streak view that makes the habit
  visible.
- **Real secrecy** — entries unreadable at rest without the owner's login password;
  a stolen disk, a leaked backup, or a curious household admin gets nothing — and,
  unlike passwords, **the titles are sealed too** (§4.1).
- **Absolute privacy by default** — no sharing, no AI, no section, no dashboard
  mention, no categorizer. Everything beyond "the owner reads their own diary" is a
  visible, per-user, off-by-default choice (D9).
- **On this day** — the payoff of years of entries: what you wrote one/five years
  ago today, surfaced while unlocked.
- **Import/export** — arrive from Day One or a folder of Markdown; leave as
  Markdown+JSON in one click (the portability half of the mission).

What we are deliberately **not** building in v1: photo/file attachments (Active
Storage blobs sit plaintext on disk, outside the envelope — Q-diary-attachments),
AI features over entries (the constraint is structural, not just postural — §8 and
Q-diary-ai), shared journals or a household timeline (a diary is one person's; a
shared *entry* is W4's small, explicit exception), and mood analytics (the D32
posture: no inferred mental-state labels the user didn't write).

---

## 2. The two decisions

### D-diary-vault. DiaryEntry is a vault container on the Credential precedent; everything is sealed except the date.

A diary entry is not a life item. It has no done-state, no reason to appear on the
Dashboard or a section page, and it must never reach a categorizer, a tool's
context, or any other model surface without the owner's explicit, standing,
per-user consent (which v1 does not even offer — §8). So `DiaryEntry` follows the
**Album/Credential precedent**: `belongs_to :user`, `include Visible`, **not**
`Sectionable`. No taggings means section-level grants structurally cannot cover it
and no `Categorize*Job` ever sees it.

Where the diary goes *further* than passwords: **there is no metadata tier.** A
credential's name and username stay AR-encrypted so the list works while locked;
a diary entry's title is as sensitive as its body, so title, body, and any
user-entered mood word all live inside the sealed payload. The one deliberate
metadata leak is **`entry_date`** (plaintext, like `totp_present` on credentials):
the locked index can render the calendar, the streak, and "217 entries since
2024" without opening anything, and that is all it can render.

Privacy posture, stated once: **private absolutely, by default.** Sharing exists
(W4) but is item-level, read-only, and per-entry — there is no "share my diary"
grant, and no section grant can ever match. Emergency access (§7) **excludes the
diary by default** and includes it only via a per-user dial with honest copy.

### D-vault-sealed. The vault crypto generalizes to a second container by extraction, not duplication — and the cookie path-scope survives it.

The password build left the machinery one refactor away from generic: `Keyring`
is already per-user and container-agnostic; `Vault::Crypto` is the only OpenSSL
file; `Credential`'s seal/unseal methods and `Vault::Share`'s
grant-plus-wrapped-key lockstep don't care what the payload is. W0 extracts —
with **zero behavior change to passwords**, proven by the existing vault suite
passing untouched:

- **`VaultSealed`** (model concern): the item-key envelope — `write_secrets!` /
  `update_secrets!` / `rotate_secrets!` / `unwrap_item_key` / `read_secrets`,
  parameterized by AAD prefix and per-reader key-row association. `Credential`
  and `DiaryEntry` both include it.
- **`VaultSession` learns a path list.** The invariant — *the unlocked key
  transits only on vault requests* — is the whole point of the path-scoped
  cookie, and widening the path to `/` would silently gut it. Instead:
  `COOKIE_PATHS = %w[ /credentials /diary ]`, one cookie per path,
  written/read/deleted in a loop. Every new sealed surface appends its prefix
  here (a registry, D-style) and nowhere else.
- **`Keyring#reset!` consults a registry, not a hand-list.** Today it destroys
  `user.credential_keys` to mark secrets lost; missing a second container there
  would be a *security* bug (orphaned wraps that still decrypt, entries that
  claim to be readable but aren't). Sealed models register a
  `mark_lost_on_reset!(user)` hook; `reset!` iterates the registry.
- **`Vault::Share` takes the sealed record**, not a credential, and the
  `AccessGrant` destroy-callback that keeps visibility and decryptability in
  lockstep generalizes the same way.
- **`VaultEvent` stays credential-shaped until W4 needs it** — the diary emits no
  events until sharing exists; the W4 migration makes the subject polymorphic
  then, not speculatively.

---

## 3. Threat model deltas (everything in PASSWORDS_PLAN §3 holds; these differ)

| Threat | Outcome |
|---|---|
| Stolen disk / backup / nosy admin reading a copy | **Defended, more completely than passwords**: no metadata tier means no AR-readable titles — an attacker with the AR keys learns *dates and counts only*. |
| Another household member, through the app | **Defended** (D9), and structurally stronger: no section clause can ever match, and until W4 there is no grant path at all. |
| Emergency contact opening the vault (§7 of PASSWORDS_PLAN) | The escrowed **vault key opens the diary key too** — this is a policy line, not a crypto line, and we say so. Diary access on emergency open is **denied by app policy, off by default**, with a per-user include dial and the honest note that shell-plus-collusion bypasses policy (the same honesty PASSWORDS_PLAN §7 already states about the waiting period). |
| Password reset without recovery code | **Total loss of all entries, by design** — and for a diary that is years of writing, not re-keyable accounts. This is why W1 gates the first entry on recovery-kit confirmation (§4.5): the failure mode is too expensive to leave the kit optional. |
| Model/AI exfiltration | **Structurally closed in v1**: entries never enter a prompt, a log, an `AppError` context, or a background job. Chat turns run in `ChatTurnJob` — key material never rides the queue — so there is no accidental path; §8 designs the deliberate one. |

---

## 4. Cryptographic architecture

Same primitives, same `Vault::Crypto`, one addition: a per-user **diary key** tier
that makes reading a whole journal cheap.

### 4.1 Why a diary key (the one place the password design doesn't transfer)

Credentials decrypt one at a time (a reveal click); their index reads AR metadata.
A diary index while unlocked wants titles and previews for *many* entries, and
search wants to scan *all* of them — but the credential scheme prices every read at
an RSA-3072 unwrap (~1–2ms on a desktop, 10–20ms on the Pi-class boxes we care
about; a thousand entries would take seconds per page view). So:

- Each user gets a random 32-byte **diary key**, stored on `diary_settings`
  wrapped under their **vault key** with AES-GCM (AAD `"diary:v1:content-key"`).
  Owner read path: *password → vault key → diary key → item keys → entries* — one
  GCM unwrap per entry, microseconds each, thousands of entries in one request.
- Each entry keeps its own **item key** (uniform with credentials — per-entry keys
  are what make per-entry sharing and rotation possible), wrapped for the owner
  under the diary key (GCM) rather than RSA. Grantee wraps (W4) stay RSA-OAEP to
  the grantee's public key in `diary_entry_keys` — the grantee path is identical
  to a credential's, one RSA unwrap for the one entry they were given.
- The owner's wrap carries a scheme byte: `\x02` = GCM-under-diary-key (normal),
  `\x01` = RSA-to-owner-public-key — the **capture-while-locked** path. Writing
  needs no unlocked vault (asymmetric wrap, exactly like credential capture);
  the next unlocked read opportunistically re-wraps to `\x02`.
- Reset semantics compose for free: the diary key is wrapped under the vault key,
  so a lost vault key kills it, and the registry hook (§2) records the loss.
  There is no re-share recovery for a diary — nobody else holds your entries'
  keys — which is exactly why §4.5 makes the recovery kit mandatory.

### 4.2 Payload

One versioned JSON payload per entry, AES-256-GCM, AAD `"diary_entry:v1"`:
`{ title:, body:, mood:, v: 1 }` — body is Markdown; `mood` is an optional word
*the user typed*, never inferred (D32). New fields are payload shape, not
migrations.

### 4.3 Unlock, lock, cookie

Nothing new: the same keyring, the same unlock-rides-sign-in, the same 12-hour
window and Lock button, the same encrypted HttpOnly session-bound cookie — now
also written with `path: "/diary"` (§2). Locked, the diary shows the calendar,
the streak, and date rows with a "Enter your password to unlock" banner; unlocked,
it opens. One lock state for the whole vault: locking passwords locks the diary
(one keyring, one mental model — a per-surface lock is a dial we'd add only if
asked for).

### 4.4 Editing and autosave

Reads and edits require the unlocked vault (the item key must be unwrapped to
merge). Autosave PATCHes the payload every ~10s of idle under the entry's
existing item key — in-request, key from the cookie, nothing queued. Entries
render server-side into the unlocked page (unlike credential secrets, which only
ever leave as no-store JSON — a diary is for *reading*); every diary response
sets `Cache-Control: no-store`, and `entry_date` is the only thing that ever
appears in a URL.

### 4.5 Recovery is mandatory here

The password vault made the recovery kit a nag (`recovery_confirmed_at`). The
diary makes it a **gate**: the first entry cannot be written until the kit is
confirmed (generating it needs only an unlocked vault — no new crypto). The copy
says why in one sentence: *"If you forget your password and lose this code, your
diary is gone — not resettable, gone."*

---

## 5. Data model

```ruby
create_table :diary_entries do |t|
  t.references :user, null: false, foreign_key: true
  t.date    :entry_date, null: false           # the one deliberate metadata leak
  t.binary  :payload_ciphertext                # GCM over {title, body, mood, v:1}
  t.binary  :owner_wrapped_item_key, null: false # scheme-byte: diary-key GCM | owner RSA
  t.datetime :edited_at                        # last content change (updated_at moves on re-wraps)
  t.timestamps
end
add_index :diary_entries, [ :user_id, :entry_date ]   # several entries a day is allowed

create_table :diary_entry_keys do |t|          # grantee wraps only (W4); owner's rides the entry row
  t.references :diary_entry, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.binary :wrapped_item_key, null: false      # RSA-OAEP to the grantee's public key
  t.timestamps
end
add_index :diary_entry_keys, [ :diary_entry_id, :user_id ], unique: true

create_table :diary_settings do |t|
  t.references :user, null: false, foreign_key: true, index: { unique: true }
  t.binary  :wrapped_content_key, null: false  # diary key under the vault key (GCM)
  t.boolean :emergency_included, null: false, default: false   # §7 dial
  t.boolean :prompts_enabled, null: false, default: true
  t.timestamps
end
```

- **`DiaryEntry`**: `include Visible` (owner clause does all the work until W4;
  the section clause never matches — no taggings), `include VaultSealed`.
  `AccessGrant::ITEM_TYPES` gains `"DiaryEntry"` (registry append) in W4, not
  before.
- **`User`** gains `has_many :diary_entries` and `has_one :diary_setting`
  (registry appends). `Keyring` itself does not change — the diary key hangs off
  `diary_settings`, so the keyring stays the container-agnostic core.

### Routes

Everything under `/diary`, the second entry in the cookie path registry:

```ruby
resources :diary_entries, path: "diary" do
  member do
    post :share                 # W4
    delete :unshare             # W4
  end
  collection do
    post :unlock                # same banner pattern as credentials
    post :lock
    post :export                # in-request, password-confirmed (W3)
    get  :import, action: :new_import   # W3
    post :import, action: :create_import
    get  :on_this_day           # W2
  end
end
```

---

## 6. UX

- **Sidebar**: `Diary` joins the Vault group (… / Notes / Mail / Passwords /
  **Diary**), `:book_open` is taken by Recipes — a `:lock_closed`-over-book or
  `:pencil` glyph joins `ICON_PATHS` (registry append).
- **Index**: a month calendar strip (dots on entry days, streak count) over a
  reverse-chronological list. Locked: dates only, unlock banner. Unlocked: title
  + first-line preview, decrypted in-request. Search is a client-visible text box
  filtering in Ruby over decrypted payloads — cheap at diary-key prices (§4.1).
- **Editor**: today's entry is one click from the index ("Write today"); a
  full-width, distraction-light editor (title optional, Markdown body, optional
  mood word), autosave chip, backdating via a date field. The D16 minimum: a
  body. Prompts (W2, `prompts_enabled`): a rotating question when the page is
  blank — first-party strings, no model call.
- **On this day** (W2): while unlocked, the index shows entries from this date in
  past years. The habit payoff, and the feature import buys instantly (§ below).
- **Import** (W3): Day One JSON export and a zip/folder of Markdown files
  (filename or front-matter dates); in-request (plaintext must not transit the
  job queue), People::Import-style dedupe report.
- **Export** (W3): Markdown files + a JSON manifest, in-request, unlocked +
  fresh-password-confirmed, exactly the passwords posture — and the M4.2 archive
  job gets a manifest line saying the diary exports separately (dates only would
  still be a leak worth avoiding; the archive carries *nothing*).
- **Sharing** (W4): per-entry, read-only, household members with initialized
  keyrings, revoke rotates the item key — the §4.5 PASSWORDS_PLAN semantics
  verbatim, via the generalized `Vault::Share`. The share card copy is
  diary-honest: *"They'll be able to read this entry until you revoke it — but
  not un-read it."* Shared-with-me entries appear in a separate "Shared with
  you" strip, never interleaved with the reader's own journal.

---

## 7. Emergency access: excluded by default

PASSWORDS_PLAN §7 escrow wraps the **vault key** — and the diary key hangs under
it, so an emergency contact who opens the vault holds the material to open the
diary. Policy, not crypto, is the only place to draw a different line, and we
draw it honestly (the same honesty §7 already applies to the waiting period):

- **By default, emergency access opens passwords and not the diary**: the diary
  controllers refuse an emergency-grant session unless `emergency_included` is
  true. Off by default, per-user, visible (D9).
- The dial's copy states both halves: *"Include your diary when your emergency
  contact opens your vault"* and, beneath it, *"This is enforced by the app, not
  by encryption — someone who controls the server itself could bypass it."*
- Both setup surfaces say which way the dial points: the emergency-contact card
  on the Passwords page notes "diary not included" (or included), and the diary
  settings link back.

---

## 8. The AI seam (designed now, deliberately not built)

A diary is simultaneously the highest-value corpus the assistant could read and
the one with the strongest reason not to let it. The structural fact settles v1:
**chat and tool turns execute in background jobs, and key material never rides
the queue** — so no existing model surface *can* read the diary, and v1 adds no
new one. What the seam looks like when it's worth building (Q-diary-ai):

- A per-user dial, off by default, D9-visible, phrased as consent to a specific
  act — *"let the assistant read my diary when I ask it to"* — never a standing
  feed into context.
- Reads happen **in-request only** (the reflection runs while the user waits,
  vault key from the cookie, like export), or the job architecture grows an
  explicit, audited hand-off; the former is the local-first answer and the
  likely v1.
- Uses that justify it: "what did I write about the move?", a year-in-review
  draft, on-this-day summaries. Uses that never ship: mood inference, agent
  nudges from diary content, anything that writes a clinical-sounding label the
  user didn't type (D32).

Nothing in W0–W4 depends on this section; it exists so the payload shape and the
consent posture don't get reopened later.

---

## 9. Build waves

Each wave lands green (`bin/rails test`, `bin/rubocop`) and independently
shippable.

| Wave | Contents |
|---|---|
| **W0 — the extraction** | D-vault-sealed, zero password behavior change: `VaultSealed` concern extracted from `Credential`; `VaultSession` cookie-path registry (loop over `COOKIE_PATHS`); `Keyring#reset!` registry hook; `Vault::Share` generalized to sealed records. The existing vault test suite must pass **unmodified** — that's the wave's acceptance test — plus new concern-level tests. |
| **W1 — the diary** | `diary_entries` / `diary_settings`; diary-key tier (lazy init at first unlocked visit); recovery-kit gate before first entry; editor with autosave, backdating, capture-while-locked (RSA wrap + opportunistic re-wrap); calendar/streak index, locked and unlocked states; `/diary` cookie path; sidebar entry, `filter_parameters` for payload params, `no-store`, rate limits on unlock. |
| **W2 — the habit** | On this day; writing prompts (first-party strings, `prompts_enabled`); search over decrypted payloads; month navigation. |
| **W3 — doors** | Import (Day One JSON, Markdown folder) and export (Markdown+JSON), both in-request; archive-job manifest line (diary carries nothing). |
| **W4 — the exception** | Per-entry sharing on the generalized `Vault::Share`: `diary_entry_keys` grantee wraps, `AccessGrant::ITEM_TYPES` append, rotate-on-revoke, shared-with-you strip; `vault_events` subject goes polymorphic and diary share/unshare events land in it; the §7 emergency dial ships here too (it's a sharing question). |
| **W5 — deferred by design** | Q-diary-ai (the §8 dial and in-request reflections) and Q-diary-attachments (needs the D-storage-seam encryption story). **Not built** until their gates clear. |

W0 and W1 carry the test weight: the extraction proves itself against the
untouched password suite; W1 adds known-answer vectors for the diary-key wrap and
both owner-wrap schemes, capture-while-locked round-trips, the re-wrap
opportunism, reset-marks-lost via the registry, the recovery gate, and a
regression asserting no payload field ever renders while locked or appears in a
log, an `AppError`, or a job argument.

---

## 10. Open questions

- **Q-diary-ai.** The §8 dial: when (and whether) the assistant may read entries,
  and the in-request execution it requires. Gated on someone wanting it more than
  they fear it; the consent shape is designed above so the wait costs nothing.
- **Q-diary-attachments.** Photos in entries want the envelope to cover Active
  Storage blobs — a D-storage-seam conversation (encrypt-at-rest service or
  per-blob GCM under the item key), not a diary-local hack. Until then, entries
  are text, and the composer says so rather than silently storing plaintext
  images next to sealed words.
