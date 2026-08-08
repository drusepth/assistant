# PASSWORDS_PLAN.md

Build plan for the **password vault**: per-account password storage under the Vault
sidebar group, so a household stores and manages its passwords on the box it owns
instead of renting a corporate password manager — and, later, uses the vault as the
home base for deciding which accounts AI agents may act on. **Status: built —
waves 1–5 landed** (see `STATUS.md`); W6 (the agent bridge) stays gated on the
agent-actuator milestone, and this document remains the design record.

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
- **Generator** — strong random passwords (and memorable passphrases) offered at
  capture time.
- **TOTP** — the vault shows the live 6-digit code next to the password, so 2FA
  stops living in one person's phone.
- **Household sharing** — the wifi password, the Netflix login, the utility account:
  shared deliberately, per item, revocable (D9; `AccessGrant` as everywhere).
- **More than logins** — wifi networks, payment cards, and sealed notes are the
  other things families keep on sticky notes; one `kind` registry covers them.
- **Import/export** — one CSV away from leaving Bitwarden/LastPass/Chrome, and one
  click away from leaving us (the portability half of the mission).
- **Emergency access** — a homebox that "lasts generations" must answer the hard
  question corporate managers dodge behind support tickets: what happens to my
  passwords if something happens to me (§7).

What we are deliberately **not** building in v1: browser autofill (needs an
extension — Q-vault-autofill), acting as a passkey *provider* (needs OS-level
WebAuthn integration; we can store recovery codes and note "this site uses a
passkey" in an entry's notes), live breach monitoring by default (network egress —
Q-vault-breach; an *offline* check ships instead, §6), and agent execution (§8
designs the seam; it builds when agent actuators exist). Without autofill this is
not yet a daily-driver replacement for a browser vault for every site — it *is* the
right home for the household's shared and high-stakes credentials, and the system of
record the extension will later sync from. We say so honestly in the UI rather than
overpromise.

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
only and read-only**: a grantee can see and reveal, never edit; rotation is the
owner's act (a folder-level convenience is Q-vault-collections).

Entries have a **`kind`** from a first-party registry (D11 style): `login` (v1),
then `wifi`, `card`, and `note` (W2) — same crypto, same sharing, kind-specific
capture fields and reveal labels. The wifi password and the shared card are the
things families actually tape to the fridge; a registry entry each is all they cost.

The hard rule, stated once and enforced everywhere: **no credential secret is ever
placed in a model prompt, a log line, an `AppError` context, or a background job.**
When agents arrive (§8), they use credentials through code-level actuators; the
model sees "logged in as drew@example.com", never the password.

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
  **recovery code** generated at vault creation and shown once. The per-user crypto
  state lives on a **`Keyring`** row (named so "vault" can keep meaning what the
  sidebar and the Documents copy already use it to mean).
- Each user gets an **RSA keypair**; the public key is stored plain, the private key
  wrapped by the vault key.
- Each credential gets its own **item key** (random 32 bytes) encrypting its secret
  payload with AES-256-GCM; the item key is stored wrapped to the public key of
  every user who may read it (`credential_keys`) — the owner is just the first
  keyholder, so **sharing is another row, not another mechanism**, and there is
  exactly one decrypt path.
- **Unlock rides sign-in**: the session controller already holds the password for
  one request, derives the KEK, unwraps the vault key, and stashes it in an
  encrypted, HttpOnly cookie **path-scoped to `/credentials`** — so the unwrapped
  key lives on the *client*, sealed under `secret_key_base`, transits only on vault
  requests, and **nothing at rest server-side can open the vault**. Day-to-day, the
  vault is simply open when you're signed in; Lock is a button, and unlocks expire
  after 12 hours.
- Two tiers of data: **metadata** (name, username, url) uses the existing AR
  `encrypts` — listable while locked, baseline-protected at rest; **secrets** are
  vault-locked. The list is visible, the secrets are sealed — the UX every password
  manager has.

Costs accepted knowingly: the login password becomes a real key (password *change*
re-wraps seamlessly; password *reset* without the recovery code loses the secrets —
§4.6), sharing requires the grantee to have an initialized keyring, and crypto rides
plain OpenSSL (PBKDF2 at OWASP-level iterations; no new native gems, per the
one-command-install principle — KDF params are stored per-keyring so an argon2id
upgrade later is a data migration, not a redesign). KDF cost is paid once per
sign-in and once per re-unlock; on Pi-class home servers that's a visible pause
(~1–2s) we accept rather than weaken the parameters.

---

## 3. Threat model (what the crypto buys, in plain terms)

| Threat | Outcome |
|---|---|
| Stolen disk, leaked backup of `storage/` + DB | **Defended.** Secrets are wrapped; the KEK never exists at rest. The AR keys in `storage/` open metadata only. |
| Nosy or malicious household admin reading a *copy* (backup, old disk, DB file) | **Defended.** Admin is a role, not a master key (the D23 principle); without a member's password or recovery code their secrets stay sealed. |
| Another household member, through the app | **Defended** (D9): private by default; `visible_to` + a `credential_keys` row are both required to read. |
| Admin (or attacker) with shell on the **running** box | **Not defended, and we say so.** Whoever controls the running app can capture keys from request memory as members sign in, or substitute a keyring's public key to intercept *future* shares. True of every server-side manager; only client-side crypto (a future extension, Q-vault-autofill) moves this line. The trust statement for the UI: *"the person who runs your home server could eventually read these; nobody who merely steals a copy of it can."* |
| XSS in the app | The practical web-vault killer: script running as the user can call reveal endpoints. Mitigated in W1 by shipping a **real, nonce-based Content-Security-Policy** (the initializer is currently commented out entirely) — see §4.8. |
| User forgets password *and* loses recovery code | **Data loss, by design.** Secrets are unrecoverable; metadata survives so entries can be re-keyed by resetting each password at the website. The recovery kit and §7's emergency contacts exist to make this rare. |
| Phishing / malware on the member's device | Out of scope, as for every password manager. |

TLS between browser and box is assumed (Kamal's Let's Encrypt path already covers
the deployed case); the reveal endpoint is useless plaintext-over-LAN otherwise, and
`docs/STORAGE.md`-style setup docs will say so. Ruby cannot reliably zero key
material in memory; we accept that (it only matters inside the already-conceded
running-box compromise).

---

## 4. Cryptographic architecture

All primitives from Ruby's bundled OpenSSL — no new gems.

- **KDF**: PBKDF2-HMAC-SHA256, 600,000 iterations (OWASP baseline), 16-byte
  per-keyring salt. Iterations and salt stored on the keyring row; version byte on
  every ciphertext so algorithms can rotate.
- **Symmetric**: AES-256-GCM, 12-byte random IV, IV‖tag‖ciphertext stored as one
  binary. Every encryption binds **AAD** (`"credential:v1:<kind>"` for secret
  payloads; analogous labels for wrapped keys) so a DB-level attacker cannot swap
  ciphertexts between rows, fields, or uses and have them decrypt.
- **Asymmetric**: RSA-3072, OAEP-SHA256, used only to wrap 32-byte item keys (chosen
  over X25519 because OpenSSL exposes it as one call; ECIES would be hand-rolled).

### 4.1 Key hierarchy

```
login password ──PBKDF2──▶ KEK ──unwraps──▶ vault key ──unwraps──▶ private key
recovery code ──PBKDF2──▶ rKEK ─unwraps──▶ vault key                   │
                                                                       ▼
credential_keys.wrapped_item_key ──RSA-OAEP decrypt──▶ item key ──AES-GCM──▶ secrets
```

One read path for everyone, owner and grantee alike: *my password → my vault key →
my private key → the item key wrapped for me → the secret.*

### 4.2 Keyring initialization (lazy, at a password-bearing moment)

The KEK can only be derived while the app momentarily holds the login password: at
sign-in, or at an explicit unlock prompt. So `Vault::Initialize` runs lazily the
first time either happens after the feature lands (and inside `/setup` and
invitation-acceptance for new users, which also collect the password): generate
vault key + keypair, wrap, persist, generate the recovery code, and — the one
non-silent step — show the **recovery kit** once (code + print/download view), with
"I saved it" confirmation recorded as `recovery_confirmed_at`.

### 4.3 Unlock, lock, and the session cookie

`SessionsController#create`, after authenticating, calls `Vault::Unlock` and writes
`cookies.encrypted[:keyring] = { user_id:, session_id:, key:, issued_at: }`
(HttpOnly, SameSite=Lax, **`path: "/credentials"`** — every vault endpoint lives
under that prefix precisely so the key never transits on any other request). Every
vault read verifies the cookie's `user_id` **and `session_id`** match the current
session (so sign-out structurally invalidates the unlock — a copied cookie dies with
its session) and `issued_at` is within the 12-hour unlock window (Q-vault-autolock
tracks whether that needs a dial; note the *session* cookie is permanent, so this
window — not sign-in — is what daily users will actually feel). Lock = delete the
cookie. A signed-in user with no valid cookie (pre-feature session, expired window,
new device) sees the Passwords page with metadata visible and a one-field "Enter
your password to unlock" banner — `POST /credentials/unlock` re-derives and re-sets
the cookie, rate-limited like the reset flow (`rate_limit to: 10, within:
3.minutes`).

### 4.4 Reveal and copy

Secrets never render into the index or show pages (so nothing lands in the Turbo
page cache). Reveal is `POST /credentials/:id/reveal` — authorized via `visible_to`
**and** the presence of a `credential_keys` row for the viewer — returning JSON over
TLS with `Cache-Control: no-store`, rate-limited generously (a human pace, not a
scraper's). A Stimulus `clipboard` controller drives both "copy" buttons (fetch →
`navigator.clipboard.writeText`, best-effort overwrite of the clipboard after 45s)
and the eye-toggle (fetch → swap into the field, cleared on blur/navigation). Every
reveal touches `last_used_at`. The TOTP variant returns the current RFC 6238 code
plus seconds remaining instead of the secret itself — the common case never exposes
the seed. (TOTP correctness depends on the box's clock: the self-hosting docs say
"run NTP", and the Passwords page shows a warning when the drift against the
browser's clock exceeds ~30s — a home-server reality corporate vaults don't have.)

### 4.5 Sharing (W3)

Sharing a credential needs two writes, so all share/revoke actions live on
credential-scoped endpoints (also required by the cookie's path scoping — the
generic `AccessGrantsController` never sees the vault key): `Vault::Share` creates
the ordinary item-level `AccessGrant` (visibility, revocation UI, D9 audit surface —
unchanged) **and** unwraps the item key with the grantor's unlocked vault, re-wraps
it to the grantee's public key, inserts the `credential_keys` row. Consequences the
UI states plainly:

- The share card offers only household members with **initialized keyrings** ("Ask
  Sam to sign in once before you can share with them").
- The grantor must be **unlocked** to share (they always are, in practice).
- Shares are **read-only**: reveal and copy, never edit; the owner rotates.
- **Revoking removes future access, not past knowledge**: destroying the grant also
  destroys the key row *and re-encrypts the secrets under a fresh item key* (cheap,
  since the revoking owner is unlocked — so even a grantee who kept a copy of the
  old wrapped key gains nothing from future database snapshots). The confirm dialog
  still offers the honest next step — "generate a new password for this account and
  save it here" — because no rotation un-knows a password someone already saw.
- "Share with everyone in the household" is the D-photos-primitive convenience:
  bulk per-member grants + key wraps, no new mechanism.

### 4.6 Password change and reset

- **Change**: the app currently has **no change-password form at all** — the only
  way to change a password today is the email-token reset flow, which is exactly
  the flow that cannot rewrap. So W1 builds Settings › "Change password"
  (`has_secure_password`'s `password_challenge` verifies the old one), and inside
  the same transaction that updates `password_digest`: derive old KEK → unwrap
  vault key → re-wrap under new KEK. Item keys and secrets untouched. This closes a
  real pre-existing gap independent of the vault.
- **Reset** (email token, old password unknown): the existing flow gains one step.
  After the new password is accepted, offer the **recovery code** field: with it,
  unwrap via rKEK and re-wrap under the new KEK — nothing lost; a fresh recovery
  code is issued. Without it, the user may proceed knowingly: vault key
  unrecoverable, secrets marked lost (`keyrings.reset_at`; entries show "secret
  lost in a password reset" with a re-enter affordance), metadata intact, a fresh
  vault key/keypair generated so the vault works going forward. Key rows *received
  from others* die with the lost private key — those owners see a one-click
  "re-share" suggestion. §7's emergency contact, when configured, is a second
  recovery path.

### 4.7 Export

The M4.2 archive job runs in background, where the vault key must never travel
(serializing key material into the Solid Queue tables would undo everything above).
So: the main export includes `credentials.jsonl` **metadata only**, with a manifest
note, and the Passwords page gets its own **"Download my passwords"** — an
in-request, unlocked-session-only CSV/JSON export (Bitwarden-compatible columns, so
leaving us is one import away), gated behind a fresh password confirmation.

### 4.8 App hardening that rides along (W1)

- **Content-Security-Policy, for real**: the initializer is currently the
  commented-out Rails scaffold — i.e., the app ships with *no* CSP. W1 enables a
  nonce-based policy app-wide (`script-src 'self'` + nonces for the importmap inline
  script, `object-src 'none'`, `frame-ancestors 'self'`), because XSS is the one
  attack that turns "server-side vault" into "no vault." App-wide, not
  vault-page-only — a stored XSS on any page runs in the same origin.
- `filter_parameters` grows every vault field name (secrets, import file, unlock
  password); reveal responses set `no-store`; secrets are excluded from `AppError`
  context by construction (the recorder never receives them).
- Reveal/unlock endpoints are POST-only, CSRF-protected, rate-limited; nothing
  secret ever appears in a URL.

---

## 5. Data model

```ruby
create_table :keyrings do |t|
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
  t.string  :kind, null: false, default: "login" # registry: login / wifi / card / note
  t.string  :name, null: false                   # AR-encrypted (metadata tier)
  t.string  :username                            # AR-encrypted
  t.string  :url                                 # AR-encrypted
  t.binary  :secrets_ciphertext                  # AES-256-GCM over a versioned JSON payload
  t.boolean :totp_present, null: false, default: false
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

- **Secrets are one versioned JSON payload per credential** (`{password:, totp:,
  notes:}` for logins; kind-specific keys otherwise), encrypted as a single GCM blob
  with the kind in the AAD — one decrypt serves any field's reveal, and new kinds
  are payload shapes, not migrations. `totp_present` is the one deliberate metadata
  leak ("this entry has 2FA") so the index can show the TOTP chip without a decrypt;
  the registry documents it.
- **`Credential`**: `include Visible` (owner + item-grant clauses do all the work;
  the section clause never matches since there are no taggings). `has_many
  :credential_keys`; destroying an access grant destroys the matching key row and
  triggers the §4.5 item-key rotation. `AccessGrant::ITEM_TYPES` gains
  `"Credential"` (registry append). Metadata columns use `encrypts` (the
  `model_profiles.api_key` setup), which forecloses SQL `LIKE`/`ORDER BY` — fine:
  per-user vaults are hundreds of rows, so the index loads the user's visible set
  and searches/sorts in Ruby.
- **`Keyring`**: `belongs_to :user`; `User` gains `has_one :keyring, dependent:
  :destroy` and `has_many :credentials, dependent: :destroy` (registry appends).
- **`Vault::Crypto`** (`app/services/vault/`): the only file that touches OpenSSL —
  KDF, wrap/unwrap, GCM encrypt/decrypt with AAD, RSA wrap/unwrap, versioned
  ciphertext framing, and the ~20-line RFC 6238 TOTP implementation (Base32 +
  HMAC-SHA1; no gem). Alongside it: `Initialize`, `Unlock`, `Rewrap` (change/
  reset), `Share`, `Reveal`, `Export`, `Import`.

### Routes

Everything under `/credentials`, so the path-scoped keyring cookie covers exactly
the vault surface and nothing else:

```ruby
resources :credentials do
  member do
    post :reveal                 # ?field=password|totp|notes|…
    post :share                  # W3: grant + key wrap
    delete :unshare              # W3: revoke + key row + item-key rotation
  end
  collection do
    post :unlock                 # the re-unlock banner
    post :lock
    post :export                 # in-request, password-confirmed (W2)
    post :recovery               # regenerate the recovery kit (unlocked only)
  end
end
```

---

## 6. UX

- **Sidebar**: `Passwords` joins the Vault group (Address Book / Photos / Documents /
  Notes / **Passwords**), `:key` icon added to `ICON_PATHS` (registry append).
- **Index**: search box autofocused; rows show name, username, and two copy buttons
  (username, password) — copy never reveals; a TOTP chip shows the live code with a
  countdown ring where `totp_present`. Kind filter chips once W2 lands. Locked
  state shows the same list with copy buttons disabled behind the unlock banner.
  Empty state leads with the importer ("Coming from another password manager?")
  next to "Add a password".
- **Capture** (D16 minimum): name + password, everything else optional; the password
  field carries a generator button — random (length/symbols toggles) **and a
  passphrase mode** (four-word diceware off a bundled wordlist; what people accept
  for passwords they must occasionally type) — Stimulus, `crypto.getRandomValues`,
  generated client-side so it exists nowhere until saved; plus a dependency-free
  entropy meter (no zxcvbn).
- **Show/edit**: reveal toggles per secret field; TOTP enrollment by pasting the
  otpauth secret or URI ("scan with your camera" is a phone habit — we accept the
  paste flow and say so); notes for security questions, recovery codes, "this site
  uses a passkey".
- **Kinds** (W2): `wifi` (network name, password — the fridge sticky note), `card`
  (number, expiry, code, PIN — the family card everyone keeps texting each other),
  `note` (sealed free text). Same list, same sharing, kind-specific field sets from
  the registry.
- **Sharing card**: the standard item card, with the vault twists from §4.5
  (eligible members only, read-only shares, rotate-on-revoke, household button).
- **Import** (W2): `Vault::Import` accepts the CSV exports of Bitwarden, LastPass,
  1Password, Chrome/Edge, and Firefox — column sniffing per known header sets, the
  People::Import dedupe convention (skip exact name+username+url matches, report
  "142 imported, 3 duplicates skipped"). Runs in-request (the file already carries
  plaintext; it must not transit the job queue).
- **Stewardship** (W4): a health panel on the Passwords page — weak / reused /
  aging, computed in-request while unlocked, never stored — plus an **offline**
  compromised-password check: the top-of-the-pwned-list bloom filter ships as a
  **local dataset on the D-public-datasets layer** (seeded small, refreshable via
  `RefreshDatasetsJob` or admin file import, vintage always displayed) — zero
  egress, the local-first answer; the live HIBP k-anonymity check stays an admin
  opt-in (Q-vault-breach).
- **Settings**: only the change-password form (§4.6); vault lifecycle lives on the
  Passwords page itself (lock, recovery kit, export, health panel).

---

## 7. Emergency access (W5) — the generational feature

A homebox that outlives its owners needs an answer to incapacity and death that
isn't "hope they wrote the master password down." The design is user-controlled
key escrow with a waiting period (the Bitwarden emergency-access pattern, on our
existing machinery):

- On the Passwords page, a user may designate a household member as their
  **emergency contact**: their vault key is wrapped to that member's public key
  (one more wrapped-key row, `wait_days` chosen at setup — default 7).
- The contact can **request access**; the owner is notified on every channel they
  have (D22) and can deny with one click, which destroys the request. If the wait
  elapses undenied, the app releases the wrapped key to the contact — read access
  to the whole vault, prominently logged.
- Honesty, stated in the setup copy: the waiting period is app-enforced policy, not
  cryptography — an emergency contact *colluding with whoever has shell on the box*
  could skip the wait (the wrapped key exists from day one). That is the correct
  trade for a household appliance, and it is the user's visible choice (D9), off by
  default.
- This doubles as a second recovery path for the forgot-everything case (§4.6), and
  it is the feature that makes the vault a place a family can consolidate for
  decades — the thing no corporate manager's support ticket queue actually
  guarantees.

---

## 8. The agent bridge (designed now, built when actuators exist)

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

Nothing in W1–W5 depends on this section; it exists so the schema and the crypto
don't have to be reopened when the agent milestone arrives.

---

## 9. Build waves

Each wave lands green (`bin/rails test`, `bin/rubocop`) and independently shippable.

| Wave | Contents |
|---|---|
| **W1 — the vault** | `Vault::Crypto` (KDF, AAD-bound GCM, RSA wrap, TOTP math) + the three tables; lazy keyring init + recovery kit; unlock-at-sign-in, lock, re-unlock banner, session-bound path-scoped cookie, 12h window; **Settings change-password form** (new — the app has none) with rewrap; reset-flow recovery step; `Credential` CRUD (`login` kind), search-first index, generator + passphrase mode, reveal/copy endpoints + clipboard controller; **app-wide nonce-based CSP**; sidebar entry, `filter_parameters`, rate limits. |
| **W2 — daily driver** | TOTP (enrollment, live codes, countdown, clock-drift warning); kinds `wifi`/`card`/`note`; `Vault::Import` (Bitwarden/LastPass/1Password/Chrome/Firefox CSV); "Download my passwords" + metadata-only line in the M4.2 archive. |
| **W3 — sharing** | `Vault::Share`/unshare on credential-scoped routes, share card with eligibility + read-only framing, grant↔key-row lockstep, **item-key rotation on revoke**, household-wide button, lost-vault re-share suggestions. |
| **W4 — stewardship** | Health panel (weak/reused/aging, in-request only); offline common-passwords list on the D-public-datasets layer. *Built as a plain line-per-password list, not a bloom filter — at the scale a household imports (tens of thousands of lines) a Set costs a megabyte and stays greppable/auditable; the bloom filter is what a 600M-row list would need, and nothing local-first ships that.* The live HIBP check and the audit trail were left out of the first pass as questions the plan hadn't answered yet; both were settled on the 2026-08 product call — live HIBP is **out for good** (offline is the whole posture, not just the default), and the audit log **shipped**: shares and emergency access only, never routine reveals (§4.9). |
| **W5 — emergency access** | §7: contact designation, wrapped-key escrow, request/deny/wait flow on D22 notification channels, prominent audit. |
| **W6 — agent bridge** | §8, gated on the agent-actuator milestone; design fixed here so waves 1–5 need no rework. **Not built.** |

W1 is the trust-critical wave and gets the test weight: known-answer vectors for
every `Vault::Crypto` operation (so a refactor that silently changes ciphertext
framing fails loudly), round-trip property tests, unlock/expiry/session-binding
cases, password change and both reset branches, share/revoke/rotation, and a
regression asserting no secret field ever appears in a rendered index/show body.

### Build notes (what the build changed about the design)

Four things the plan didn't anticipate, decided during the build:

- **The keyring's own key rows are the "secret lost" marker.** `Keyring#reset!`
  deletes the user's `credential_keys` rather than setting a flag on each
  credential: the rows are what make a secret readable, so deleting them *is*
  the loss, and no per-entry state can drift out of sync with the crypto.
  `Credential#secret_lost_for?` is a query, not a column.
- **Re-entering a lost secret rotates rather than writes.** The edit path for a
  lost entry mints a fresh item key wrapped for the owner *and every grantee
  whose key row survived* — so a re-entered household password reaches the
  people it was already shared with, without a re-share round trip.
- **`kind` is immutable after creation**, because it's sealed into the AAD.
  The edit form submits it but the controller drops it; changing an entry's
  kind means creating a new one. Cheap, and it keeps the AAD binding honest.
- **The unlock window is what expires, not the session.** The existing session
  cookie is permanent, so a member who leaves a tab open for a day meets the
  unlock banner, not a sign-in page — exactly the surface Q-vault-autolock is
  about. Tests must re-unlock after `travel`ing past 12 hours.

---

## 10. Questions, answered and open

Four of the five were settled on the 2026-08 product call, after the build:

- **Q-vault-autolock — resolved: keep 12h + manual Lock.** A family desktop isn't a
  corporate laptop, and an over-eager lock sends people back to a browser vault.
  Expiry is already gentle (metadata stays listed; the banner takes a password
  inline). A per-user idle dial is deferred, not rejected — the obvious v2 if a
  household with a shared machine asks.
- **Q-vault-collections — resolved for now: item-level only.** The Q15 pattern:
  don't build the org-vault key model speculatively. Item-level is the honest unit
  for a secret, and a folder quietly widens blast radius as it fills. If the tedium
  bites, a bulk multi-select share fixes most of it with no new crypto; a keyed
  collection stays available after that.
- **Q-vault-audit — resolved and built: shares and emergency access, never
  reveals.** See §4.9.
- **Q-vault-breach — resolved: offline only, no live HIBP even as an opt-in.** A box
  whose pitch is that it doesn't phone home shouldn't ship a feature whose selling
  point is phoning home, k-anonymity or not. Stated limit: this catches weak and
  widely-known passwords, not "your password appeared in a named breach."

Still open:

- **Q-vault-autofill.** The real daily-driver gap. A browser extension (or passkey
  provider role) is a separate product surface with its own threat model — and the
  natural place client-side crypto (true zero-knowledge, moving the §3 running-box
  line) would land. Design conversation of its own when the vault proves out.

### 4.9 The audit log (Q-vault-audit as built)

`vault_events` is owner-visible and carries names and verbs only — never a
secret. It records `shared` / `unshared` and the emergency lifecycle
(`emergency_added`, `_revoked`, `_requested`, `_denied`, `_opened`), surfaced as
a **Sharing history** card on the entry and a **Vault activity** strip on the
Passwords page with emergency lines highlighted. Recording follows the D23
posture: a failure to log is logged to `app_errors`, never raised at the user.

Reveals are deliberately excluded. They're the owner's own clicks, `last_used_at`
already answers "when did I last use this", and a log that fills with
self-generated noise buries the two events a household member actually needs to
see. Entry-scoped events die with their credential; vault-wide events survive it.
When agents can touch credentials (§8), agent use is the next thing that belongs
in this table — which is the case that made a log worth building now rather than
retrofitting later.
