# STORAGE.md

Where your files live. Documents, photos, and export archives are stored through
Active Storage; **which backend holds the bytes is instance configuration, not
code** (D32). Two backends ship:

- **`local`** (the default) — files on the app server's disk under `storage/`.
  Zero configuration. Right for a home server whose disk you already back up.
- **`s3`** — any S3-*compatible* object store: AWS S3, Cloudflare R2, Backblaze
  B2, or a self-hosted MinIO. Right when you want durability, capacity, and the
  photo library's bandwidth served by the bucket instead of the app.

Nothing about the app changes between them; switch by setting ENV and restarting.

## Configuration

| ENV | Meaning |
|---|---|
| `ACTIVE_STORAGE_SERVICE` | `local` (default), `s3`, or `mirror` (migration only) |
| `STORAGE_BUCKET` | Bucket name (create it yourself; keep it **private**) |
| `STORAGE_ACCESS_KEY_ID` / `STORAGE_SECRET_ACCESS_KEY` | Credentials scoped to that one bucket |
| `STORAGE_REGION` | Region (default `us-east-1`; R2 uses `auto`, MinIO ignores it) |
| `STORAGE_ENDPOINT` | Leave unset for AWS. R2: `https://<account_id>.r2.cloudflarestorage.com`. B2: `https://s3.<region>.backblazeb2.com`. MinIO: your server, e.g. `http://192.168.1.10:9000` |
| `STORAGE_FORCE_PATH_STYLE` | `true` for MinIO (and most other self-hosted stores) |

Example — MinIO on the LAN:

```sh
ACTIVE_STORAGE_SERVICE=s3
STORAGE_ENDPOINT=http://192.168.1.10:9000
STORAGE_FORCE_PATH_STYLE=true
STORAGE_BUCKET=assistant
STORAGE_ACCESS_KEY_ID=...
STORAGE_SECRET_ACCESS_KEY=...
```

## CORS for direct uploads

Photo uploads go **browser → bucket** (a signed direct upload), so the bucket
must allow PUT from your instance's origin. Apply this CORS policy, with your
instance's URL in place of the example:

```json
[
  {
    "AllowedOrigins": ["https://assistant.example.com"],
    "AllowedMethods": ["PUT"],
    "AllowedHeaders": ["Content-Type", "Content-MD5", "Content-Disposition"],
    "MaxAgeSeconds": 3600
  }
]
```

- **AWS**: bucket → Permissions → CORS. **R2**: bucket → Settings → CORS policy.
  **B2**: `b2 bucket update --cors-rules`. **MinIO**: `mc admin config set`
  or the console's bucket settings.
- If direct uploads fail with a CORS error in the browser console, this policy
  (or the origin in it) is what's wrong. Uploads through ordinary forms
  (documents) don't need CORS — they pass through the app.

## Serving

Downloads and photo views are **short-lived signed redirect URLs**: the app
authorizes the request (everything renders behind `visible_to`), then redirects
the browser to the bucket, which serves the bytes. Keep the bucket private — the
signed URLs are the only access path, and they expire.

## Migrating an existing instance from local to S3

1. Configure the `STORAGE_*` variables (test: `ACTIVE_STORAGE_SERVICE=s3` on a
   throwaway instance should boot and accept an upload).
2. Set `ACTIVE_STORAGE_SERVICE=mirror` and restart — new uploads now land on
   both local disk and the bucket.
3. Copy the existing blobs across:

   ```sh
   bin/rails runner '
     configs = Rails.application.config.active_storage.service_configurations
     s3 = ActiveStorage::Service.configure(:s3, configs)
     ActiveStorage::Blob.find_each do |blob|
       next if s3.exist?(blob.key)
       blob.open { |file| s3.upload(blob.key, file, checksum: blob.checksum) }
       print "."
     rescue ActiveStorage::FileNotFoundError
       puts "\nmissing locally, skipped: #{blob.key}"
     end
   '
   ```

4. Set `ACTIVE_STORAGE_SERVICE=s3` and restart. Once you're confident, the
   `storage/` directory on disk is redundant (the SQLite databases also live
   under `storage/` — don't delete the directory itself).

## Backup posture

- `local`: back up the `storage/` volume — it holds both the SQLite databases
  and the files. That was true before this seam and stays true.
- `s3`: the databases still live on the app server (back those up); the bucket
  holds the files. Turn on the store's versioning if you want delete-protection;
  lifecycle rules are yours to choose. The per-user export (Settings) remains
  the user-level escape hatch either way.
