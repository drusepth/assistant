# PHOTOS_PLAN.md

Build plan for **household photos**: family-wide photo storage, tagging, albums, and
sharing, with S3-compatible object storage as a first-class (but optional) backing
store. **Status: built — all five waves landed** (see `STATUS.md`); this document
remains the design record.

Decisions here are logged as **D31–D32** in `DECISIONS.md`. Open questions are
logged as **Q14–Q16**. Operator-facing storage setup lives in `docs/STORAGE.md`.

---

## 1. What we're building and why

Photos are the most emotionally valuable data an ordinary family owns, and today they
rent its custody: Google Photos and iCloud own the library, the sharing graph, and the
exit costs. A self-hosted household photo library is the purest expression of the
mission — the memory layer *is* the durable asset, and this is the memory people
actually care about losing. It is also the feature most likely to make every member of
a household log in weekly, which everything else in the app benefits from.

The industry standard we're aiming at (the Google Photos / Immich baseline):

- **Zero-friction capture** — drag a folder in, multi-select from a phone, watch
  progress bars; duplicates skipped automatically.
- **Timeline browsing** — a fast thumbnail grid grouped by month, ordered by when the
  photo was *taken* (EXIF), not when it was uploaded; a full-screen lightbox with
  keyboard/swipe navigation.
- **Albums** — user-curated containers, one photo in many albums, cover photos.
- **Tagging people** — photos link to the People primitive, so a person's page shows
  their photos and a photo names who's in it.
- **Sharing** — private by default (D9), shared deliberately: per-album, per-photo, or
  "share with the whole household" in one click.
- **Durable storage** — originals in object storage the household controls (their own
  S3 bucket, Cloudflare R2, Backblaze B2, or a MinIO box in the closet), with the app
  serving fast derived thumbnails.

What we are deliberately **not** building in v1: ML face recognition/clustering,
geo-clustered map views, video (Q16), and collaborative albums where members add
photos to each other's albums (Q15). Each has a place later; none is needed for the
library to be the family's system of record.

---

## 2. The two decisions

### D31. Photo is the seventh primitive; albums are containers; sharing rides access grants.

A photo is not a Document. Documents are files-with-understanding (extracted text, AI
summary, one-at-a-time vault items); photos are high-volume visual items with their
own capture date, their own browsing idiom (grid + lightbox, not rows), their own
joins (albums, people), and no text-extraction pipeline. Overloading `Document` with a
`kind` flag would bend every vault view and the analysis pipeline around a case they
weren't built for. So: **`Photo` joins Event/Task/Document/Person/Goal/Note as the
seventh primitive** — `belongs_to :user`, `include Visible`, `include Sectionable`,
multi-taggable like everything else (a photo of Mom at the marathon = People +
Health). Photos surface through a new top-level **Photos view** (a cross-section lens
in the sidebar, like the Documents vault), not through a new section.

**Albums are user-owned containers, not sections.** The lens rule (D5: sections never
own tables) doesn't apply — an album is deliberate curation ("Summer 2026"), not a
filter, and one photo lives in many albums via a join. Albums are themselves `Visible`
(item-level grants make an album openable by a grantee), and the photo read path gains
one clause: *a photo is visible to anyone holding a grant on an album containing it,
when the grant's grantor is the photo's owner*. That mirrors the existing
section-grant clause exactly — `AccessGrant` stays the single sharing mechanism and
`visible_to` stays the single read path (D9), just with a fourth OR branch.

**Household-wide sharing is a convenience, not a new mechanism**: "Share with
everyone" on an album (or the Photos settings card) bulk-creates ordinary per-member
grants. A member who joins the household later sees nothing until someone shares again
— that's D9 working as designed, not a bug to engineer around.

### D32. Blob storage is a config seam: pick a service the way you pick a model.

The app is model-agnostic by mission; storage gets the same treatment. Active Storage
already abstracts the service — we make the choice **an instance-level configuration**
instead of a code edit:

- `config/storage.yml` grows an **`s3` service defined entirely from ENV** —
  `STORAGE_ENDPOINT` (blank for AWS), `STORAGE_REGION`, `STORAGE_BUCKET`,
  `STORAGE_ACCESS_KEY_ID`, `STORAGE_SECRET_ACCESS_KEY`,
  `STORAGE_FORCE_PATH_STYLE` (MinIO needs `true`). One shape covers AWS S3,
  Cloudflare R2, Backblaze B2, and self-hosted MinIO — S3-compatible is the protocol,
  Amazon is just one vendor.
- **`ACTIVE_STORAGE_SERVICE`** (default `local`) selects the service in
  `production.rb`. Local disk remains the zero-config default — a family on a home
  server with backups loses nothing; S3 is for durability, capacity, and bandwidth
  offload, not a requirement.
- **Direct uploads**: photo uploads go browser → bucket via Active Storage's signed
  direct-upload flow (`@rails/activestorage` through importmap), so a 200-photo batch
  never funnels through the Rails process. Requires a documented CORS policy on the
  bucket (we ship the JSON to paste). On the `local` service the same JS path works
  and uploads hit the app — one code path, two backends.
- **Delivery stays redirect-mode** (Rails default): image URLs are short-lived signed
  redirects to the bucket, so S3 serves the bytes. URLs are unguessable and expiring;
  every *page* that renders them is behind `visible_to`. The `aws-sdk-s3` gem joins
  the Gemfile.
- **Migration path**: switching an existing instance to S3 = configure the `mirror`
  service (already sketched in storage.yml), run a one-off mirror rake task to copy
  existing blobs, flip `ACTIVE_STORAGE_SERVICE`, drop the mirror. Documented, not
  automated, in v1.
- Bucket hygiene docs (not code): private bucket, versioning on if you want
  delete-protection, no public access, lifecycle rules left to the owner.

---

## 3. Data model

```ruby
create_table :photos do |t|
  t.references :user, null: false, foreign_key: true
  t.string  :title                    # optional; photos usually don't have one
  t.text    :caption                  # user- or AI-written
  t.datetime :taken_at, null: false   # EXIF DateTimeOriginal, else upload time
  t.decimal :latitude,  precision: 10, scale: 6
  t.decimal :longitude, precision: 10, scale: 6
  t.string  :ingest_status, default: "queued"  # queued/processing/ready/failed
  t.timestamps
end
add_index :photos, [ :user_id, :taken_at ]

create_table :albums do |t|
  t.references :user, null: false, foreign_key: true
  t.string :title, null: false
  t.text   :description
  t.references :cover_photo, foreign_key: { to_table: :photos }
  t.timestamps
end

create_table :album_photos do |t|
  t.references :album, null: false, foreign_key: true
  t.references :photo, null: false, foreign_key: true
  t.integer :position
  t.timestamps
end
add_index :album_photos, [ :album_id, :photo_id ], unique: true

create_table :photo_people do |t|
  t.references :photo,  null: false, foreign_key: true
  t.references :person, null: false, foreign_key: true
  t.timestamps
end
add_index :photo_people, [ :photo_id, :person_id ], unique: true
```

- **`Photo`**: `Visible` + `Sectionable`, `has_one_attached :image` with named,
  **preprocessed** variants — `:thumb` (~400px, WEBP, quality ~80, metadata stripped)
  for the grid, `:large` (~1600px, WEBP, metadata stripped) for the lightbox.
  Originals are never modified. `has_many :albums, through: :album_photos`;
  `has_many :people, through: :photo_people`.
- **`Album`**: `Visible` (not `Sectionable` — albums are curation, not life-sections).
  Cover photo falls back to the newest photo in the album.
- **Visibility**: the album clause from D31 lands as a small extension point in
  `Visible` (a class-level extra-clause hook that only `Photo` uses), so
  `Photo.visible_to(viewer)` remains the one read path. In v1 albums contain only the
  owner's photos, so the `grantor_id = photos.user_id` guard is naturally satisfied;
  it stays in the SQL anyway so Q15 (contributions) can't accidentally leak.
- **People tagging is manual** (the Q8 lesson: guessed signals cost trust; no ML face
  matching in v1). Tagging someone requires the Person be visible to you; the tag
  names, it never grants — a grantee viewing a shared photo sees tags only for people
  *they* can see.
- **Dedupe by checksum** (the importer convention): Active Storage already computes a
  base64 MD5 per blob; after upload, an incoming photo whose blob checksum matches an
  existing photo of the same user is destroyed and reported ("3 duplicates skipped"),
  not stored twice.

### Ingestion pipeline

`PhotosController#create` accepts a batch of signed blob ids (direct upload) → creates
one `Photo` per blob (`ingest_status: queued`) → `IngestPhotoJob` per photo:

1. **EXIF extract** (ruby-vips, already installed): `DateTimeOriginal` → `taken_at`
   (fallback: blob creation time), GPS → `latitude`/`longitude`, orientation handled
   by the variant processor. Deterministic, no LLM.
2. **Dedupe check** as above.
3. **Preprocess variants** so the grid and lightbox never block on-the-fly.
4. Mark `ready`; failures record to `AppError` (D23) and mark `failed` with a retry
   button on the photo page. The grid shows `queued/processing` photos as shimmering
   placeholders via the usual Turbo refresh.

No LLM call anywhere in ingestion — capture stays zero-friction and free (D16's
spirit; unlike documents there's nothing to auto-file until the model can see images,
which is Wave 5's optional garnish).

---

## 4. UX

### Uploading

- **Photos index header**: an "Add photos" button + the whole grid as a drag-drop
  target (Stimulus controller). Multi-file `<input type="file" accept="image/*"
  multiple>`; on mobile this opens the photo picker natively.
- Direct-upload progress per file (Stimulus listening to `direct-upload:*` events),
  batch summary on completion ("24 added, 3 duplicates skipped").
- Albums have the same affordance scoped to the album (upload → auto-added).

### Browsing

- **Photos view** (sidebar, above/below Documents): month-grouped thumbnail grid,
  newest first by `taken_at`, paginated by month with a "load more" Turbo frame —
  fast at 10,000 photos because the grid renders only `:thumb` WEBPs.
- **Filters** along the top (the Documents-vault convention): by album, by person, by
  section chip, by year. All are `visible_to`-scoped queries.
- **Lightbox** (Stimulus): full-screen `:large` variant, arrow-key/swipe navigation
  within the current filter, and a detail rail — date, albums, people chips, section
  chips, caption, and (owner-only) location + the Manage/Share links.
- **Photo show page** remains the plain fallback (and the share surface, like every
  primitive's show page); the lightbox is progressive enhancement over it.
- **Person pages** get a photo strip (photos tagged with that person, visible to the
  viewer). Section pages count photos in their Browse zone like other primitives.

### Albums

- Album index (own + shared-with-me), album show = cover header + its grid + the
  standard sharing card. Create/rename/describe/delete; delete removes the container
  only, never the photos. Add-to-album from the lightbox rail and via multi-select
  in the grid (checkbox mode → "Add to album / Remove" bulk bar).

### Sharing

- The standard item-level sharing card (existing `access_grants` UI) on album and
  photo show pages — an album grant is the normal unit ("share Summer 2026 with
  Grandma's account").
- **"Share with everyone in the household"** button on the album sharing card =
  bulk per-member grants (D31). Revoking is per-grant, as everywhere.
- Shared viewers see `:thumb`/`:large` variants with **metadata stripped** (the
  variants already strip EXIF); location coordinates render only for the owner
  (Q14 tracks whether that needs to be a visible dial).

---

## 5. Later waves' garnish (designed now, built when reached)

- **AI captioning/auto-filing (optional)**: `ModelProfile` gains a user-set "model
  accepts images" toggle (we can't detect it; the owner knows their model). When on,
  a photo page offers "Describe" → `CaptionPhotoJob` sends the `:large` variant as a
  data-URL image part through the existing OpenAI-compatible adapter → caption +
  suggested section chips, suggest-and-click like document analysis. Off or absent =
  the feature simply isn't there (the D13 AI-lite posture).
- **"On this day" watcher**: deterministic SQL (photos where `taken_at` is N years ago
  this week), Quiet-dial suggestion linking into the timeline, fingerprinted per year
  so a dismissal sticks (the goal-stall convention).
- **Export/ops**: `Users::Export` grows photos (originals) + an albums manifest;
  `/admin` gets a storage panel — active service, reachability, per-member byte/photo
  *counts* (never contents — D9, the error-log convention).

---

## 6. Build waves

Each wave lands green (`bin/rails test`, `bin/rubocop`) and independently shippable.

| Wave | Contents |
|---|---|
| **W1 — storage seam (D32)** | ENV-driven `s3` service + `ACTIVE_STORAGE_SERVICE` selector, `aws-sdk-s3` gem, direct-upload JS plumbing, self-hosting docs (per-vendor setup + CORS JSON + mirror migration). No user-visible change. |
| **W2 — the primitive (D31 core)** | `photos` table + model + `IngestPhotoJob` (EXIF, dedupe, variants), batch upload UI, Photos view (timeline + filters by section/year), lightbox, photo show/edit/delete, sidebar entry, export inclusion. |
| **W3 — albums + sharing** | `albums`/`album_photos`, the `Visible` album clause, album CRUD + covers, multi-select/add-to-album, sharing cards + household-wide button, shared-with-me album index. |
| **W4 — people + polish** | `photo_people` + tagging UI (lightbox rail + show page), person-page photo strip, person filter, section-page Browse counts, `/admin` storage panel. |
| **W5 — optional garnish** | Vision toggle + `CaptionPhotoJob`, "On this day" watcher. |

W1 and W2 are independent until deploy (photos work on `local`), but W1 goes first so
real instances start on durable storage from photo one.

---

## 7. Open questions (logged as Q14–Q16)

- **Q14. Location privacy dial.** v1: variants strip EXIF, coordinates shown to the
  owner only. Is an explicit per-album "share locations" toggle warranted, or is
  owner-only forever the right D9 answer?
- **Q15. Collaborative albums.** Members adding *their* photos to a shared album
  (grants would need `grantor = photo.user_id` per contribution — the guard is
  already in the SQL). Real family demand, real complexity; decide after W3 usage.
- **Q16. Video.** Wants ffmpeg in the image, preview generation, size limits, maybe
  streaming ranges. Separate plan when photos prove out; the schema (a `Photo` with a
  different content type) shouldn't need to change.
