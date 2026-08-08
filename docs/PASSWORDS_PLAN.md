# PASSWORDS_PLAN.md

Build plan for the **password vault**: per-account password storage under the Vault
sidebar group, so a household stores and manages its passwords on the box it owns
instead of renting a corporate password manager — and, later, uses the vault as the
home base for deciding which accounts AI agents may act on. **Status: designed; build
not started.**

Decisions here are logged as **D-passwords-vault** and **D-vault-crypto** in
`DECISIONS.md`. Open questions are logged as **Q-vault-autolock, Q-vault-collections,
Q-vault-audit, Q-vault-breach, Q-vault-autofill**.

---

## 1. What we're building and why

Passwords are the keys to everything else the app protects, and today most families
rent their custody: 1Password and LastPass subscriptions, or a browser vault owned by
Google. A household password vault is squarely on mission — the credentials layer is
part of the durable memory asset, and it is the single strongest daily-use magnet in
the product ("homebox" thinking: the thing every member touches every day, for
generations). It is also the necessary substrate for the agent endgame: an assistant
that acts on your accounts needs a place where *you* decide, per account, what it may
touch (D20's proposes/disposes discipline, applied to credentials).

The bar we're aiming at (the Bitwarden-self-hosted baseline, minus the parts that
need a browser extension):

- **Search-first list** — every login findable in two keystrokes; copy username or
  password without ever showing it on screen.
- **Real secrecy** — secrets unreadable at rest without the owner's login password;
  a stolen disk, a leaked backup, or a curious household admin gets nothing.
- **Generator** — strong random passwords offered at capture time.
- **TOTP** — the vault shows the live 6-digit code next to the password, so 2FA
  stops living in one person's phone.
- **Household sharing** — the wifi password, the Netflix login, the utility account:
  shared deliberately, per item, revocable (D9; `AccessGrant` as everywhere).
- **Import/export** — one CSV away from leaving Bitwarden/LastPass/Chrome, and one
  click away from leaving us (the portability half of the mission).

What we are deliberately **not** building in v1: browser autofill (needs an
extension — Q-vault-autofill), acting as a passkey *provider* (needs OS-level
WebAuthn integration; we can store recovery codes and note "this site uses a
passkey" in an entry's notes), breach monitoring by default (network egress —
Q-vault-breach), and agent execution (§7 designs the seam; it builds when agent
actuators exist). Without autofill this is not yet a daily-driver replacement for a
browser vault for every site — it *is* the right home for the household's shared
and high-stakes credentials, and the system of record the extension will later sync
from. We say so honestly in the UI rather than overpromise.

---

## 2. The two decisions

### D-passwords-vault. Credential is a vault container, not a primitive; secrets never enter a model prompt.

A password entry is not a life item. It has no date, no done-state, no reason to
appear on the Dashboard, the Calendar, or a section page, and — decisively — it must
never be fed to a categorizer, a tool's `section_context`, or any other LLM surface.
So `Credential` follows the **Album precedent**: `belongs_to :user`, `include
Visible`, **not** `Sectionable`, surfaced through a new **Passwords** entry in the
sidebar's Vault group (`/credentials` — the model is named `Credential` because
`resources :passwords` and `PasswordsController` are already Rails 8 auth's
password-*reset* flow). No `Categorize*Job`, no section chips, no tool reads it.
Because credentials carry no `section_taggings`, section-level grants ("share all my
Money items") structurally cannot cover them — credential sharing is **item-level
only**, which is exactly right for secrets (a folder-level convenience is
Q-vault-collections).

The hard rule, stated once and enforced everywhere: **no credential secret is ever
placed in a model prompt, a log line, an `AppError` context, or an export that runs
outside the owner's unlocked session.** When agents arrive (§7), they use
credentials through code-level actuators; the model sees "logged in as
drew@example.com", never the password.

### D-vault-crypto. Secrets get envelope encryption keyed off the login password; the server holds nothing that opens them at rest.

This is a deliberate departure from the defer-hardening posture (D10/D14). The
existing AR-encryption keys live in `storage/` *next to the database, on purpose*,
so backups carry the keys with the data — right for API keys, fatal for a password
manager: anyone holding a backup (or shell on the box, or the admin role) would read
every password in the household. "Self-host instead of 1Password" is only a credible
pitch if we can say: **at rest, this server cannot read your secrets.**

The scheme is the standard password-manager key hierarchy, server-side (we are not
zero-knowledge — the server sees plaintext transiently while serving a reveal; §3
is honest about that):

- Each user's **vault key** (random 32 bytes) is stored only *wrapped*: once under a
  KEK derived from their **login password**, once under a KEK derived from a
  **recovery code** generated at vault creation and shown once.
- Each user gets an **RSA keypair**; the public key is stored plain, the private key
  wrapped by the vault key.
- Each credential gets its own **item key** (random 32 bytes) encrypting its secret
  fields (password, TOTP secret, notes) with AES-256-GCM; the item key is stored
  wrapped to the public key of every user who may read it (`credential_keys`) — the
  owner is just the first keyholder, so **sharing is another row, not another
  mechanism**, and there is exactly one decrypt path.
- **Unlock rides sign-in**: the session controller already holds the password for
  one request, derives the KEK, unwraps the vault key, and stashes it in an
  encrypted, HttpOnly cookie — so the unwrapped key lives on the *client*, sealed
  under `secret_key_base`, and **nothing at rest server-side can open the vault**.
  Day-to-day, the vault is simply open when you're signed in; Lock is a button, and
  unlocks expire after 12 hours.
- Two tiers of data: **metadata** (name, username, url) uses the existing AR
  `encrypts` — listable while locked, baseline-protected at rest; **secrets** are
  vault-locked. The list is visible, the secrets are sealed — the UX every password
  manager has.

Costs accepted knowingly: the login password becomes a real key (password *change*
re-wraps seamlessly; password *reset* without the recovery code loses the secrets —
§4.6), sharing requires the grantee to have an initialized vault, and crypto rides
plain OpenSSL (PBKDF2 at OWASP-level iterations; no new native gems, per the
one-command-install principle — KDF params are stored per-vault so an argon2id
upgrade later is a data migration, not a redesign).

---

## 3. Threat model (what the crypto buys, in plain terms)

| Threat | Outcome |
|---|---|
| Stolen disk, leaked backup of `storage/` + DB | **Defended.** Secrets are wrapped; the KEK never exists at rest. The AR keys in `storage/` open metadata only. |
| Nosy or malicious household admin (console/shell access, offline) | **Defended.** Admin is a role, not a master key (the D23 principle); without a member's password or recovery code their secrets stay sealed. |
| Another household member, through the app | **Defended** (D9): private by default; `visible_to` + a `credential_keys` row are both required to read. |
| Attacker who compromises the *running* app | **Not defended.** They can capture keys from request memory or cookies as sessions arrive. True of every server-side manager; only client-side crypto (a future extension, Q-vault-autofill) moves this line. |
| User forgets password *and* loses recovery code | **Data loss, by design.** Secrets are unrecoverable; metadata survives so entries can be re-keyed by resetting each password at the website. The recovery kit exists to make this rare. |
| Phishing / malware on the member's device | Out of scope, as for every password manager. |

TLS between browser and box is assumed (Kamal's Let's Encrypt path already covers
the deployed case); the reveal endpoint is useless plaintext-over-LAN otherwise, and
`docs/STORAGE.md`-style setup docs will say so.

---

## 4. Cryptographic architecture

All primitives from Ruby's bundled OpenSSL — no new gems.

- **KDF**: PBKDF2-HMAC-SHA256, 600,000 iterations (OWASP 2023 baseline), 16-byte
  per-vault salt. Iterations and salt stored on the vault row; version byte on every
  ciphertext so algorithms can rotate.
- **Symmetric**: AES-256-GCM, 12-byte random IV, IV‖tag‖ciphertext stored as one
  binary.
- **Asymmetric**: RSA-3072, OAEP-SHA256, used only to wrap 32-byte item keys.

### 4.1 Key hierarchy

```
login password ──PBKDF2──▶ KEK ──unwraps──▶ vault key ──unwraps──▶ private key
recovery code ──PBKDF2──▶ rKEK ─unwraps──▶ vault key                   │
                                                                       ▼
credential_keys.wrapped_item_key ──RSA-OAEP decrypt──▶ item key ──AES-GCM──▶ secrets
```

One read path for everyone, owner and grantee alike: *my password → my vault key →
my private key → the item key wrapped for me → the secret.*

### 4.2 Vault initialization (lazy, at a password-bearing moment)

The KEK can only be derived while the app momentarily holds the login password: at
sign-in, or at an explicit unlock prompt. So `Vault::Initialize` runs lazily the
first time either happens after the feature lands (and inside `/setup` and
invitation-acceptance for new users, which also collect the password): generate
vault key + keypair, wrap, persist, generate the recovery code, and — the one
non-silent step — show the **recovery kit** once (code + print/download view), with
"I saved it" confirmation recorded as `recovery_confirmed_at`.

### 4.3 Unlock, lock, and the session cookie

`SessionsController#create`, after authenticating, calls `Vault::Unlock` and writes
`cookies.encrypted[:vault_key] = { user_id:, key:, issued_at: }` (HttpOnly,
SameSite=Lax — the same flags the session cookie already uses). Every vault read
verifies the cookie's `user_id` matches `Current.user` and `issued_at` is within the
12-hour unlock window (Q-vault-autolock tracks whether that needs a dial). Lock =
delete the cookie; sign-out already clears cookies. A signed-in user with no valid
cookie (pre-feature session, expired window, new device) sees the Passwords page
with metadata visible and a one-field "Enter your password to unlock" banner —
`Vault::Unlocks#create` re-derives and re-sets the cookie, rate-limited like the
reset flow (`rate_limit to: 10, within: 3.minutes`).

### 4.4 Reveal and copy

Secrets never render into the index or show pages (so nothing lands in the Turbo
page cache). Reveal is `POST /credentials/:id/reveal` — authorized via `visible_to`
**and** the presence of a `credential_keys` row for the viewer — returning JSON over
TLS with `Cache-Control: no-store`. A Stimulus `clipboard` controller drives both
"copy" buttons (fetch → `navigator.clipboard.writeText`, best-effort overwrite of
the clipboard after 45s) and the eye-toggle (fetch → swap into the field, cleared on
blur/navigation). Every reveal touches `last_used_at`. The TOTP variant returns the
current RFC 6238 code plus seconds remaining instead of the secret itself — the
common case never exposes the seed.

### 4.5 Sharing (W3)

Sharing a credential needs two writes, so it routes through a credential-specific
endpoint (`Vault::Share`) rather than the generic `AccessGrantsController`: create
the ordinary item-level `AccessGrant` (visibility, revocation UI, D9 audit surface —
unchanged) **and** unwrap the item key with the grantor's unlocked vault, re-wrap it
to the grantee's public key, insert the `credential_keys` row. Consequences the UI
states plainly:

- The share card offers only household members with **initialized vaults** ("Ask
  Sam to sign in once before you can share with them").
- The grantor must be **unlocked** to share (they always are, in practice).
- **Revoking removes future access, not past knowledge**: destroying the grant also
  destroys the key row (a `Credential` callback keeps the two in lockstep), and the
  confirm dialog offers the honest next step — "generate a new password for this
  account and save it here."
- "Share with everyone in the household" is the D-photos-primitive convenience:
  bulk per-member grants + key wraps, no new mechanism.

### 4.6 Password change and reset

- **Change** (Settings, knows current password): derive old KEK → unwrap vault key →
  re-wrap under new KEK. One column update inside the same transaction that updates
  `password_digest`. Item keys and secrets untouched.
- **Reset** (email token, old password unknown): the existing flow gains one step.
  After the new password is accepted, offer the **recovery code** field: with it,
  unwrap via rKEK and re-wrap under the new KEK — nothing lost; a fresh recovery
  code is issued. Without it, the user may proceed knowingly: vault key
  unrecoverable, secrets marked lost (`vaults.reset_at`; entries show "secret lost
  in a password reset" with a re-enter affordance), metadata intact, a fresh vault
  key/keypair generated so the vault works going forward. Key rows *received from
  others* are re-wrapped by asking those owners to re-share (their entries show a
  one-click "re-share" suggestion) — their secrets were never wrapped to the lost
  key's mercy, only the keypair's, which is also lost.

### 4.7 Export

The M4.2 archive job runs in background, where the vault key must never travel
(serializing key material into the Solid Queue tables would undo everything above).
So: the main export includes `credentials.jsonl` **metadata only**, with a manifest
note, and the Passwords page gets its own **"Download my passwords"** — an
in-request, unlocked-session-only CSV/JSON export (Bitwarden-compatible columns, so
leaving us is one import away), gated behind a fresh password confirmation.

---

## 5. Data model

```ruby
create_table :vaults do |t|
  t.references :user, null: false, foreign_key: true, index: { unique: true }
  t.string  :key_salt, null: false
  t.integer :kdf_iterations, null: false, default: 600_000
  t.binary  :wrapped_key, null: false            # vault key under the password KEK
  t.string  :recovery_salt
  t.binary  :recovery_wrapped_key                # vault key under the recovery KEK
  t.datetime :recovery_confirmed_at
  t.text    :public_key, null: false             # PEM, plaintext by design
  t.binary  :wrapped_private_key, null: false    # under the vault key
  t.datetime :reset_at                           # last lost-vault reset, if any
  t.timestamps
end

create_table :credentials do |t|
  t.references :user, null: false, foreign_key: true
  t.string  :name, null: false                   # AR-encrypted (metadata tier)
  t.string  :username                            # AR-encrypted
  t.string  :url                                 # AR-encrypted
  t.binary  :password_ciphertext                 # item-key tier (AES-256-GCM)
  t.binary  :totp_ciphertext
  t.binary  :notes_ciphertext
  t.datetime :secret_changed_at                  # for the aging report (W4)
  t.datetime :last_used_at
  t.timestamps
end

create_table :credential_keys do |t|
  t.references :credential, null: false, foreign_key: true
  t.references :user, null: false, foreign_key: true
  t.binary :wrapped_item_key, null: false        # RSA-OAEP to this user's public key
  t.timestamps
end
add_index :credential_keys, [ :credential_id, :user_id ], unique: true
```

- **`Credential`**: `include Visible` (owner + item-grant clauses do all the work;
  the section clause never matches since there are no taggings). `has_many
  :credential_keys`; destroying an access grant destroys the matching key row.
  `AccessGrant::ITEM_TYPES` gains `"Credential"` (registry append). Metadata columns
  use `encrypts` (the `model_profiles.api_key` setup), which forecloses SQL
  `LIKE`/`ORDER BY` — fine: per-user vaults are hundreds of rows, so the index page
  loads the user's visible set and searches/sorts in Ruby.
- **`Vault`**: `belongs_to :user`; `User` gains `has_one :vault, dependent:
  :destroy` and `has_many :credentials, dependent: :destroy` (registry appends).
- **`Vault::Crypto`** (`app/services/vault/`): the only file that touches OpenSSL —
  KDF, wrap/unwrap, GCM encrypt/decrypt, RSA wrap/unwrap, versioned ciphertext
  framing, and the ~20-line RFC 6238 TOTP implementation (Base32 + HMAC-SHA1; no
  gem). Alongside it: `Initialize`, `Unlock`, `Rewrap` (change/reset), `Share`,
  `Reveal`, `Export`, `Import`.
- **Hygiene**: `filter_parameters` grows the vault field names; reveal responses set
  `no-store`; secrets are excluded from `AppError` context by construction (the
  error recorder never receives them).

### Routes

```ruby
resources :credentials do
  member { post :reveal }        # ?field=password|totp|notes
end
resource :vault, only: [] do
  post :unlock                   # the re-unlock banner
  post :lock
  post :export                   # in-request, password-confirmed (W2)
  post :recovery                 # regenerate the recovery kit (unlocked only)
end
```

---

## 6. UX

- **Sidebar**: `Passwords` joins the Vault group (Address Book / Photos / Documents /
  Notes / **Passwords**), `:key` icon added to `ICON_PATHS` (registry append).
- **Index**: search box autofocused; rows show name, username, and two copy buttons
  (username, password) — copy never reveals; a TOTP chip shows the live code with a
  countdown ring where a seed exists. Locked state shows the same list with copy
  buttons disabled behind the unlock banner. Empty state leads with the importer
  ("Coming from another password manager?") next to "Add a password".
- **Capture** (D16 minimum): name + password, everything else optional; the password
  field carries a generator button (Stimulus, `crypto.getRandomValues`, length and
  symbols toggles, generated client-side so it exists nowhere until saved) and a
  basic entropy meter (dependency-free estimate, no zxcvbn).
- **Show/edit**: reveal toggles per secret field; TOTP enrollment by pasting the
  otpauth secret or URI ("scan with your camera" is a phone habit — we accept the
  paste flow and say so); notes for security questions, recovery codes, "this site
  uses a passkey".
- **Sharing card**: the standard item card, with the vault twists from §4.5 (eligible
  members only, rotate-on-revoke nudge, household button).
- **Import** (W2): `Vault::Import` accepts the CSV exports of Bitwarden, LastPass,
  1Password, Chrome/Edge, and Firefox — column sniffing per known header sets, the
  People::Import dedupe convention (skip exact name+username+url matches, report
  "142 imported, 3 duplicates skipped"). Runs in-request (the file already carries
  plaintext; it must not transit the job queue), then the browser is told to clear
  the file input.
- **Settings**: nothing new — vault lifecycle lives on the Passwords page itself
  (lock button, recovery kit regeneration, export, and W4's health report).

---

## 7. The agent bridge (designed now, built when actuators exist)

The stated endgame: this vault becomes the home base for **which accounts an AI
agent may act on, on the user's behalf**. The design that squares it with
D-vault-crypto:

- Each credential gets an **agent dial, off by default** — per-item, visible,
  user-controlled configuration (the D9 posture; a D26-style scope, not a blanket).
- Flipping it on wraps the item key to an **instance agent keypair** (one more
  `credential_keys`-shaped row with a non-user keyholder — the schema anticipates
  this as its only planned extension), created on first use with its private key
  under the existing AR encryption. The UI states the trade in one sentence: *"the
  server can use this password while you're away; it stays sealed for everything
  else."* Default-off means the at-rest guarantee of §3 holds for every credential
  the user hasn't deliberately delegated.
- Agents consume credentials through **code actuators only** (form-login drivers,
  API clients — the D-career-web leash pattern extended): the actuator decrypts,
  authenticates, and reports outcomes; the model chooses *which account* from
  metadata and receives *"signed in as …"* — never the secret (D-passwords-vault's
  hard rule).
- Every agent use lands in the item's audit surface (`last_used_at` now; the W4/
  Q-vault-audit log when it exists) — the user can always see what the agent
  touched.

Nothing in W1–W4 depends on this section; it exists so the schema and the crypto
don't have to be reopened when the agent milestone arrives.

---

## 8. Build waves

Each wave lands green (`bin/rails test`, `bin/rubocop`) and independently shippable.

| Wave | Contents |
|---|---|
| **W1 — the vault** | `Vault::Crypto` + the three tables; lazy initialization + recovery kit; unlock-at-sign-in, lock, re-unlock banner, 12h window; password-change rewrap + reset-flow recovery step; `Credential` CRUD, search-first index, generator, reveal/copy endpoints + clipboard controller; sidebar entry, `filter_parameters`, rate limits. |
| **W2 — daily driver** | TOTP (enrollment, live codes, countdown); `Vault::Import` (Bitwarden/LastPass/1Password/Chrome/Firefox CSV); "Download my passwords" + metadata-only line in the M4.2 archive. |
| **W3 — sharing** | `Vault::Share`, share card with eligibility + rotate-on-revoke copy, grant↔key-row lockstep, household-wide button, lost-vault re-share suggestions. |
| **W4 — stewardship** | Health report (weak/reused/aging — computed in-request while unlocked, never stored); `secret_changed_at` surfacing; optional HIBP breach check behind an admin opt-in (Q-vault-breach); reveal/copy audit trail if Q-vault-audit resolves yes. |
| **W5 — agent bridge** | §7, gated on the agent-actuator milestone; design fixed here so waves 1–4 need no rework. |

W1 is the trust-critical wave and gets the test weight: round-trip crypto vectors,
unlock/expiry/binding cases, password change and both reset branches, and a
regression asserting no secret field ever appears in a rendered index/show body.

---

## 9. Open questions

- **Q-vault-autolock.** Is unlock-rides-sign-in with a 12-hour window and a manual
  Lock the right default for a family desktop, or does reveal need a per-user
  re-prompt dial (e.g., "ask for my password again after 15 minutes idle")? Decide
  from real household use, not up front.
- **Q-vault-collections.** Item-level sharing only, by design — but "the household
  folder" (a shared collection with its own key, the org-vault pattern) would spare
  re-sharing each new common credential. Real demand check after W3, like Q15.
- **Q-vault-audit.** Is `last_used_at` enough, or do reveals/copies/shares deserve
  an event log (owner-visible per item)? Leaning yes once agents can touch
  credentials; noise risk before then.
- **Q-vault-breach.** HIBP's k-anonymity range API leaks only a 5-char hash prefix,
  but it is still egress from a box whose posture is local-first. Admin opt-in at
  most; never default-on.
- **Q-vault-autofill.** The real daily-driver gap. A browser extension (or Passkey
  provider role) is a separate product surface with its own threat model — and the
  natural place client-side crypto (true zero-knowledge) would land. Design
  conversation of its own when the vault proves out.
