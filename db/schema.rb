# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_23_074818) do
  create_table "access_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "grantee_id", null: false
    t.integer "grantor_id", null: false
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["grantee_id", "subject_type", "subject_id"], name: "index_access_grants_on_grantee_and_subject"
    t.index ["grantee_id"], name: "index_access_grants_on_grantee_id"
    t.index ["grantor_id", "grantee_id", "subject_type", "subject_id"], name: "index_access_grants_uniqueness", unique: true
    t.index ["grantor_id"], name: "index_access_grants_on_grantor_id"
    t.index ["subject_type", "subject_id"], name: "index_access_grants_on_subject"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "album_photos", force: :cascade do |t|
    t.integer "album_id", null: false
    t.datetime "created_at", null: false
    t.integer "photo_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["album_id", "photo_id"], name: "index_album_photos_on_album_id_and_photo_id", unique: true
    t.index ["album_id"], name: "index_album_photos_on_album_id"
    t.index ["photo_id"], name: "index_album_photos_on_photo_id"
  end

  create_table "albums", force: :cascade do |t|
    t.integer "cover_photo_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["cover_photo_id"], name: "index_albums_on_cover_photo_id"
    t.index ["user_id"], name: "index_albums_on_user_id"
  end

  create_table "app_errors", force: :cascade do |t|
    t.text "backtrace"
    t.json "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "error_class", null: false
    t.text "message", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["created_at"], name: "index_app_errors_on_created_at"
    t.index ["source", "created_at"], name: "index_app_errors_on_source_and_created_at"
    t.index ["user_id"], name: "index_app_errors_on_user_id"
  end

  create_table "budget_categories", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "group", default: "needs", null: false
    t.integer "monthly_target_cents"
    t.string "name", null: false
    t.integer "position"
    t.string "target_set_by"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "name"], name: "index_budget_categories_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_budget_categories_on_user_id"
  end

  create_table "care_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "interval_months"
    t.string "kind_key", null: false
    t.string "label"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "kind_key"], name: "index_care_settings_on_user_id_and_kind_key", unique: true
    t.index ["user_id"], name: "index_care_settings_on_user_id"
  end

  create_table "credential_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "credential_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.binary "wrapped_item_key", null: false
    t.index ["credential_id", "user_id"], name: "index_credential_keys_on_credential_id_and_user_id", unique: true
    t.index ["credential_id"], name: "index_credential_keys_on_credential_id"
    t.index ["user_id"], name: "index_credential_keys_on_user_id"
  end

  create_table "credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "login", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "secret_changed_at"
    t.binary "secrets_ciphertext"
    t.boolean "totp_present", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id", null: false
    t.string "username"
    t.index ["user_id"], name: "index_credentials_on_user_id"
  end

  create_table "diary_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "edited_at"
    t.date "entry_date", null: false
    t.integer "lock_version", default: 0, null: false
    t.binary "owner_wrapped_item_key", null: false
    t.binary "payload_ciphertext"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "entry_date"], name: "index_diary_entries_on_user_id_and_entry_date"
    t.index ["user_id"], name: "index_diary_entries_on_user_id"
  end

  create_table "diary_entry_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "diary_entry_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.binary "wrapped_item_key", null: false
    t.index ["diary_entry_id", "user_id"], name: "index_diary_entry_keys_on_diary_entry_id_and_user_id", unique: true
    t.index ["diary_entry_id"], name: "index_diary_entry_keys_on_diary_entry_id"
    t.index ["user_id"], name: "index_diary_entry_keys_on_user_id"
  end

  create_table "diary_imports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "cursor", default: 0, null: false
    t.integer "imported", default: 0, null: false
    t.binary "payload_ciphertext", null: false
    t.integer "skipped", default: 0, null: false
    t.string "source_label"
    t.integer "total", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_diary_imports_on_user_id"
  end

  create_table "diary_revisions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "diary_entry_id", null: false
    t.binary "payload_ciphertext", null: false
    t.datetime "updated_at", null: false
    t.index ["diary_entry_id", "created_at"], name: "index_diary_revisions_on_diary_entry_id_and_created_at"
    t.index ["diary_entry_id"], name: "index_diary_revisions_on_diary_entry_id"
  end

  create_table "diary_settings", force: :cascade do |t|
    t.datetime "content_key_reset_at"
    t.datetime "created_at", null: false
    t.boolean "emergency_included", default: false, null: false
    t.boolean "prompts_enabled", default: true, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.binary "wrapped_content_key", null: false
    t.index ["user_id"], name: "index_diary_settings_on_user_id", unique: true
  end

  create_table "document_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id", null: false
    t.string "fingerprint", null: false
    t.integer "item_id", null: false
    t.string "item_type", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_document_items_on_document_id"
    t.index ["item_type", "item_id"], name: "index_document_items_on_item"
  end

  create_table "documents", force: :cascade do |t|
    t.string "analysis_error"
    t.string "analysis_status"
    t.datetime "created_at", null: false
    t.text "description"
    t.json "extracted_facts", default: {}, null: false
    t.text "extracted_text"
    t.boolean "health_plan"
    t.json "landings", default: [], null: false
    t.json "suggested_sections", default: []
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_documents_on_user_id"
  end

  create_table "email_sender_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "rule", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "email"], name: "index_email_sender_rules_on_user_id_and_email", unique: true
    t.index ["user_id"], name: "index_email_sender_rules_on_user_id"
  end

  create_table "emergency_contacts", force: :cascade do |t|
    t.integer "contact_user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "released_at"
    t.datetime "requested_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "wait_days", default: 7, null: false
    t.binary "wrapped_vault_key", null: false
    t.index ["contact_user_id"], name: "index_emergency_contacts_on_contact_user_id"
    t.index ["user_id", "contact_user_id"], name: "index_emergency_contacts_on_user_id_and_contact_user_id", unique: true
    t.index ["user_id"], name: "index_emergency_contacts_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.boolean "all_day", default: false, null: false
    t.string "care_kind"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ends_at"
    t.integer "goal_id"
    t.string "location"
    t.datetime "starts_at", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["goal_id"], name: "index_events_on_goal_id"
    t.index ["starts_at"], name: "index_events_on_starts_at"
    t.index ["user_id"], name: "index_events_on_user_id"
  end

  create_table "feed_items", force: :cascade do |t|
    t.string "author"
    t.datetime "created_at", null: false
    t.integer "feed_id", null: false
    t.string "guid", null: false
    t.datetime "published_at"
    t.datetime "read_at"
    t.datetime "routed_at"
    t.datetime "saved_at"
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["feed_id", "guid"], name: "index_feed_items_on_feed_id_and_guid", unique: true
    t.index ["feed_id", "published_at"], name: "index_feed_items_on_feed_id_and_published_at"
    t.index ["feed_id", "routed_at"], name: "index_feed_items_on_feed_id_and_routed_at"
    t.index ["feed_id"], name: "index_feed_items_on_feed_id"
    t.index ["read_at"], name: "index_feed_items_on_read_at"
    t.index ["saved_at"], name: "index_feed_items_on_saved_at"
  end

  create_table "feeds", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.boolean "broad"
    t.datetime "classified_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "etag"
    t.integer "failure_count", default: 0, null: false
    t.string "kind", default: "rss", null: false
    t.string "label"
    t.string "last_error"
    t.datetime "last_fetched_at"
    t.datetime "last_item_at"
    t.string "last_modified"
    t.datetime "last_read_at"
    t.string "site_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "user_id", null: false
    t.index ["last_fetched_at"], name: "index_feeds_on_last_fetched_at"
    t.index ["user_id", "url"], name: "index_feeds_on_user_id_and_url", unique: true
    t.index ["user_id"], name: "index_feeds_on_user_id"
  end

  create_table "goals", force: :cascade do |t|
    t.datetime "broken_down_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "shape"
    t.integer "status", default: 1, null: false
    t.date "target_on"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_goals_on_user_id"
  end

  create_table "happening_matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "happening_id", null: false
    t.string "reason"
    t.datetime "rejected_at"
    t.integer "section_id"
    t.string "source", default: "model", null: false
    t.string "target", null: false
    t.datetime "updated_at", null: false
    t.index ["happening_id", "target"], name: "index_happening_matches_on_happening_id_and_target", unique: true
    t.index ["happening_id"], name: "index_happening_matches_on_happening_id"
    t.index ["section_id", "rejected_at"], name: "index_happening_matches_on_section_id_and_rejected_at"
    t.index ["section_id"], name: "index_happening_matches_on_section_id"
  end

  create_table "happenings", force: :cascade do |t|
    t.boolean "all_day", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "distance_mi", precision: 8, scale: 1
    t.datetime "ends_at"
    t.integer "event_id"
    t.date "expires_on"
    t.datetime "hidden_at"
    t.string "kind", default: "event", null: false
    t.datetime "last_seen_at"
    t.decimal "latitude", precision: 10, scale: 6
    t.integer "listing_source_id", null: false
    t.string "location"
    t.decimal "longitude", precision: 10, scale: 6
    t.datetime "matched_at"
    t.boolean "out_of_range", default: false, null: false
    t.string "provenance", default: "listed", null: false
    t.string "series_uid"
    t.datetime "starts_at"
    t.integer "task_id"
    t.string "title", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.datetime "withdrawn_at"
    t.index ["event_id"], name: "index_happenings_on_event_id"
    t.index ["listing_source_id", "starts_at"], name: "index_happenings_on_listing_source_id_and_starts_at"
    t.index ["listing_source_id", "uid"], name: "index_happenings_on_listing_source_id_and_uid", unique: true
    t.index ["listing_source_id"], name: "index_happenings_on_listing_source_id"
    t.index ["matched_at"], name: "index_happenings_on_matched_at"
    t.index ["series_uid"], name: "index_happenings_on_series_uid"
    t.index ["task_id"], name: "index_happenings_on_task_id"
  end

  create_table "hobby_briefs", force: :cascade do |t|
    t.datetime "authored_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.integer "section_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["section_id"], name: "index_hobby_briefs_on_section_id"
    t.index ["user_id", "section_id"], name: "index_hobby_briefs_on_user_id_and_section_id", unique: true
    t.index ["user_id"], name: "index_hobby_briefs_on_user_id"
  end

  create_table "households", force: :cascade do |t|
    t.text "address"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.string "home_status"
    t.date "moved_in_on"
    t.string "name", null: false
    t.string "phone"
    t.boolean "public_pages_enabled", default: true, null: false
    t.string "region"
    t.string "tagline"
    t.string "time_zone"
    t.datetime "updated_at", null: false
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.integer "inviter_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_invitations_on_household_id"
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
  end

  create_table "job_feeds", force: :cascade do |t|
    t.string "api_key"
    t.datetime "created_at", null: false
    t.string "kind", default: "rss", null: false
    t.string "label"
    t.string "last_error"
    t.datetime "last_scanned_at"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_job_feeds_on_user_id"
  end

  create_table "keyrings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kdf_iterations", null: false
    t.string "key_salt", null: false
    t.text "public_key", null: false
    t.datetime "recovery_confirmed_at"
    t.string "recovery_salt"
    t.datetime "recovery_verified_at"
    t.binary "recovery_wrapped_key"
    t.datetime "reset_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.binary "wrapped_key", null: false
    t.binary "wrapped_private_key", null: false
    t.index ["user_id"], name: "index_keyrings_on_user_id", unique: true
  end

  create_table "linked_accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "credentials", default: "{}", null: false
    t.json "disabled_scopes", default: [], null: false
    t.string "label"
    t.string "provider", null: false
    t.json "settings", default: {}, null: false
    t.string "sync_error"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "provider"], name: "index_linked_accounts_on_user_id_and_provider"
    t.index ["user_id"], name: "index_linked_accounts_on_user_id"
  end

  create_table "listing_sources", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "credentials"
    t.string "etag"
    t.integer "failure_count", default: 0, null: false
    t.string "kind", default: "ics", null: false
    t.string "last_error"
    t.datetime "last_fetched_at"
    t.datetime "last_item_at"
    t.string "last_modified"
    t.integer "place_id", null: false
    t.string "provider"
    t.json "settings", default: {}, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["last_fetched_at"], name: "index_listing_sources_on_last_fetched_at"
    t.index ["place_id", "url"], name: "index_listing_sources_on_place_id_and_url", unique: true
    t.index ["place_id"], name: "index_listing_sources_on_place_id"
  end

  create_table "model_profiles", force: :cascade do |t|
    t.boolean "allow_cloud_models", default: true, null: false
    t.string "api_key"
    t.string "base_url", default: "https://api.openai.com/v1", null: false
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "model", default: "gpt-4o-mini"
    t.string "provider", default: "openai", null: false
    t.datetime "updated_at", null: false
    t.boolean "vision", default: false, null: false
    t.boolean "web_capable", default: false, null: false
    t.index ["household_id"], name: "index_model_profiles_on_household_id", unique: true
  end

  create_table "notes", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "kind", default: "plain", null: false
    t.string "severity"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "notification_channels", force: :cascade do |t|
    t.json "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "kind", null: false
    t.text "secrets", default: "{}", null: false
    t.integer "sent_count", default: 0, null: false
    t.date "sent_on"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "kind"], name: "index_notification_channels_on_user_id_and_kind"
    t.index ["user_id"], name: "index_notification_channels_on_user_id"
  end

  create_table "people", force: :cascade do |t|
    t.text "address"
    t.date "birthday"
    t.datetime "created_at", null: false
    t.string "email"
    t.boolean "keep_in_touch", default: false, null: false
    t.date "last_contacted_on"
    t.integer "linked_user_id"
    t.string "name", null: false
    t.text "notes"
    t.string "phone"
    t.string "pronoun"
    t.string "relationship"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["linked_user_id"], name: "index_people_on_linked_user_id"
    t.index ["user_id"], name: "index_people_on_user_id"
  end

  create_table "pet_foods", force: :cascade do |t|
    t.decimal "amount_per_day", precision: 8, scale: 2
    t.string "brand"
    t.datetime "created_at", null: false
    t.date "ended_on"
    t.string "form", default: "dry", null: false
    t.string "name", null: false
    t.text "notes"
    t.date "opened_on"
    t.decimal "package_amount", precision: 10, scale: 2
    t.integer "package_cost_cents"
    t.string "package_unit", default: "g", null: false
    t.integer "pet_id", null: false
    t.date "started_on", null: false
    t.string "unit", default: "g", null: false
    t.datetime "updated_at", null: false
    t.index ["pet_id"], name: "index_pet_foods_on_pet_id"
  end

  create_table "pet_vaccinations", force: :cascade do |t|
    t.string "administered_by"
    t.datetime "created_at", null: false
    t.integer "document_id"
    t.date "due_on"
    t.integer "duration_months"
    t.integer "event_id"
    t.date "given_on", null: false
    t.string "kind", default: "dose", null: false
    t.string "lot_number"
    t.string "name", null: false
    t.text "notes"
    t.integer "pet_id", null: false
    t.string "product"
    t.text "reaction"
    t.integer "series_dose"
    t.string "site"
    t.string "tag_number"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "vaccine_key"
    t.integer "vet_id"
    t.index ["document_id"], name: "index_pet_vaccinations_on_document_id"
    t.index ["event_id"], name: "index_pet_vaccinations_on_event_id"
    t.index ["pet_id", "due_on"], name: "index_pet_vaccinations_on_pet_id_and_due_on"
    t.index ["pet_id", "vaccine_key", "given_on"], name: "index_pet_vaccinations_on_pet_id_and_vaccine_key_and_given_on"
    t.index ["pet_id"], name: "index_pet_vaccinations_on_pet_id"
    t.index ["user_id"], name: "index_pet_vaccinations_on_user_id"
    t.index ["vet_id"], name: "index_pet_vaccinations_on_vet_id"
  end

  create_table "pets", force: :cascade do |t|
    t.date "adopted_on"
    t.date "born_on"
    t.boolean "born_on_estimated", default: false, null: false
    t.string "breed"
    t.string "color"
    t.datetime "created_at", null: false
    t.date "died_on"
    t.date "left_on"
    t.string "microchip"
    t.string "name", null: false
    t.boolean "neutered", default: false, null: false
    t.text "notes"
    t.string "pronoun"
    t.integer "section_id", null: false
    t.string "sex"
    t.string "species", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "vet_id"
    t.decimal "weight_lb", precision: 6, scale: 2
    t.index ["section_id"], name: "index_pets_on_section_id", unique: true
    t.index ["user_id"], name: "index_pets_on_user_id"
    t.index ["vet_id"], name: "index_pets_on_vet_id"
  end

  create_table "photo_people", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "person_id", null: false
    t.integer "photo_id", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_photo_people_on_person_id"
    t.index ["photo_id", "person_id"], name: "index_photo_people_on_photo_id_and_person_id", unique: true
    t.index ["photo_id"], name: "index_photo_people_on_photo_id"
  end

  create_table "photos", force: :cascade do |t|
    t.text "caption"
    t.string "caption_error"
    t.string "caption_status"
    t.datetime "created_at", null: false
    t.string "ingest_error"
    t.string "ingest_status", default: "queued", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.json "suggested_sections", default: []
    t.datetime "taken_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "taken_at"], name: "index_photos_on_user_id_and_taken_at"
    t.index ["user_id"], name: "index_photos_on_user_id"
  end

  create_table "places", force: :cascade do |t|
    t.boolean "alerts", default: true, null: false
    t.string "country"
    t.datetime "created_at", null: false
    t.datetime "last_opened_at"
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.integer "lead_days", default: 14, null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "radius_mi", default: 25, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "position"], name: "index_places_on_user_id_and_position"
    t.index ["user_id"], name: "index_places_on_user_id"
  end

  create_table "recipe_book_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position"
    t.integer "recipe_book_id", null: false
    t.integer "recipe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recipe_book_id", "recipe_id"], name: "index_recipe_book_entries_on_recipe_book_id_and_recipe_id", unique: true
    t.index ["recipe_book_id"], name: "index_recipe_book_entries_on_recipe_book_id"
    t.index ["recipe_id"], name: "index_recipe_book_entries_on_recipe_id"
  end

  create_table "recipe_books", force: :cascade do |t|
    t.integer "cover_recipe_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["cover_recipe_id"], name: "index_recipe_books_on_cover_recipe_id"
    t.index ["user_id"], name: "index_recipe_books_on_user_id"
  end

  create_table "recipe_ingredients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "heading", default: false, null: false
    t.string "item", null: false
    t.string "item_key", null: false
    t.string "note"
    t.boolean "optional", default: false, null: false
    t.integer "position", null: false
    t.decimal "quantity", precision: 10, scale: 3
    t.string "raw", null: false
    t.integer "recipe_id", null: false
    t.string "unit"
    t.datetime "updated_at", null: false
    t.index ["item_key"], name: "index_recipe_ingredients_on_item_key"
    t.index ["recipe_id", "position"], name: "index_recipe_ingredients_on_recipe_id_and_position"
    t.index ["recipe_id"], name: "index_recipe_ingredients_on_recipe_id"
  end

  create_table "recipes", force: :cascade do |t|
    t.integer "cook_minutes"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "directions"
    t.boolean "favorite", default: false, null: false
    t.string "import_error"
    t.text "import_source"
    t.string "import_status"
    t.date "last_cooked_on"
    t.text "notes"
    t.integer "prep_minutes"
    t.integer "servings"
    t.string "source_name"
    t.string "source_url"
    t.integer "times_cooked", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "title"], name: "index_recipes_on_user_id_and_title"
    t.index ["user_id"], name: "index_recipes_on_user_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "deliver_at", null: false
    t.datetime "delivered_at"
    t.datetime "last_delivered_at"
    t.integer "lead_minutes"
    t.string "rule"
    t.boolean "schedule", default: false, null: false
    t.boolean "silent", default: false, null: false
    t.integer "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["delivered_at", "deliver_at"], name: "index_reminders_on_delivered_at_and_deliver_at"
    t.index ["subject_type", "subject_id"], name: "index_reminders_on_subject_type_and_subject_id"
    t.index ["user_id"], name: "index_reminders_on_user_id"
  end

  create_table "review_items", force: :cascade do |t|
    t.text "answer"
    t.datetime "created_at", null: false
    t.float "difficulty"
    t.datetime "due_at"
    t.integer "kind", default: 0, null: false
    t.integer "lapses", default: 0, null: false
    t.datetime "last_reviewed_at"
    t.text "prompt", null: false
    t.integer "reps", default: 0, null: false
    t.float "stability"
    t.integer "state", default: 0, null: false
    t.integer "topic_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["topic_id"], name: "index_review_items_on_topic_id"
    t.index ["user_id", "due_at"], name: "index_review_items_on_user_id_and_due_at"
    t.index ["user_id"], name: "index_review_items_on_user_id"
  end

  create_table "section_taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "section_id", null: false
    t.integer "taggable_id", null: false
    t.string "taggable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["section_id", "taggable_type", "taggable_id"], name: "index_section_taggings_uniqueness", unique: true
    t.index ["section_id"], name: "index_section_taggings_on_section_id"
    t.index ["taggable_type", "taggable_id"], name: "index_section_taggings_on_taggable"
  end

  create_table "sections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "custom", default: false, null: false
    t.string "name", null: false
    t.integer "parent_id"
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_sections_on_parent_id"
    t.index ["slug"], name: "index_sections_on_slug", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "share_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "label"
    t.datetime "last_viewed_at"
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "views_count", default: 0, null: false
    t.index ["subject_type", "subject_id"], name: "index_share_links_on_subject"
    t.index ["token"], name: "index_share_links_on_token", unique: true
    t.index ["user_id"], name: "index_share_links_on_user_id"
  end

  create_table "spending_accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "csv_mapping"
    t.string "kind", default: "checking", null: false
    t.string "last4"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_spending_accounts_on_user_id"
  end

  create_table "spending_rules", force: :cascade do |t|
    t.integer "budget_category_id", null: false
    t.datetime "created_at", null: false
    t.string "matcher", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["budget_category_id"], name: "index_spending_rules_on_budget_category_id"
    t.index ["user_id", "matcher"], name: "index_spending_rules_on_user_id_and_matcher", unique: true
    t.index ["user_id"], name: "index_spending_rules_on_user_id"
  end

  create_table "spotted_hobbies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "feed_ids", default: [], null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.text "reason"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "name"], name: "index_spotted_hobbies_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_spotted_hobbies_on_user_id"
  end

  create_table "stays", force: :cascade do |t|
    t.string "booking_status", default: "planned", null: false
    t.date "check_in", null: false
    t.date "check_out", null: false
    t.string "confirmation_code"
    t.integer "cost_cents"
    t.datetime "created_at", null: false
    t.string "kind", default: "airbnb", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.string "location", null: false
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name"
    t.text "notes"
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["trip_id", "check_in"], name: "index_stays_on_trip_id_and_check_in"
    t.index ["trip_id"], name: "index_stays_on_trip_id"
  end

  create_table "story_routings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "feed_item_id", null: false
    t.string "reason"
    t.datetime "rejected_at"
    t.integer "section_id", null: false
    t.string "source", default: "model", null: false
    t.datetime "updated_at", null: false
    t.index ["feed_item_id", "section_id"], name: "index_story_routings_on_feed_item_id_and_section_id", unique: true
    t.index ["feed_item_id"], name: "index_story_routings_on_feed_item_id"
    t.index ["section_id", "rejected_at"], name: "index_story_routings_on_section_id_and_rejected_at"
    t.index ["section_id"], name: "index_story_routings_on_section_id"
  end

  create_table "study_logs", force: :cascade do |t|
    t.integer "activity", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "minutes", null: false
    t.string "note"
    t.date "on", null: false
    t.integer "subject_id"
    t.integer "topic_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["subject_id"], name: "index_study_logs_on_subject_id"
    t.index ["topic_id"], name: "index_study_logs_on_topic_id"
    t.index ["user_id", "on"], name: "index_study_logs_on_user_id_and_on"
    t.index ["user_id"], name: "index_study_logs_on_user_id"
  end

  create_table "subjects", force: :cascade do |t|
    t.string "commons_key"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "interest_frame"
    t.integer "status", default: 0, null: false
    t.date "target_date"
    t.string "title", null: false
    t.datetime "tree_built_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_subjects_on_user_id"
  end

  create_table "suggestions", force: :cascade do |t|
    t.json "action", default: {}, null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.string "kind", default: "nudge", null: false
    t.date "snoozed_until"
    t.string "status", default: "pending", null: false
    t.string "title", null: false
    t.integer "tool_run_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "watcher_slug", null: false
    t.index ["tool_run_id"], name: "index_suggestions_on_tool_run_id"
    t.index ["user_id", "fingerprint"], name: "index_suggestions_on_user_id_and_fingerprint", unique: true
    t.index ["user_id", "status"], name: "index_suggestions_on_user_id_and_status"
    t.index ["user_id"], name: "index_suggestions_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "bucket", default: 0, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.date "due_on"
    t.integer "goal_id"
    t.json "guiding_questions", default: [], null: false
    t.text "notes"
    t.string "remind_time"
    t.string "repeat_rule"
    t.text "resolution"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["bucket"], name: "index_tasks_on_bucket"
    t.index ["due_on"], name: "index_tasks_on_due_on"
    t.index ["goal_id"], name: "index_tasks_on_goal_id"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "tool_run_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.string "item_type", null: false
    t.integer "tool_run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["item_type", "item_id"], name: "index_tool_run_items_on_item"
    t.index ["tool_run_id", "item_type", "item_id"], name: "index_tool_run_items_on_tool_run_id_and_item_type_and_item_id", unique: true
    t.index ["tool_run_id"], name: "index_tool_run_items_on_tool_run_id"
  end

  create_table "tool_run_messages", force: :cascade do |t|
    t.string "client_token"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.integer "tool_run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tool_run_id", "created_at"], name: "index_tool_run_messages_on_tool_run_id_and_created_at"
    t.index ["tool_run_id"], name: "index_tool_run_messages_on_tool_run_id"
  end

  create_table "tool_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error"
    t.json "inputs", default: {}, null: false
    t.string "origin", default: "user", null: false
    t.json "output", default: {}, null: false
    t.datetime "recap_requested_at"
    t.string "status", default: "queued", null: false
    t.integer "subject_id"
    t.string "subject_type"
    t.string "tool_slug", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["subject_type", "subject_id"], name: "index_tool_runs_on_subject"
    t.index ["user_id", "created_at"], name: "index_tool_runs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_tool_runs_on_user_id"
  end

  create_table "topics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "goal_id"
    t.date "mastered_on"
    t.integer "mastery", default: 0, null: false
    t.string "mastery_evidence"
    t.integer "parent_id"
    t.integer "position", default: 1, null: false
    t.integer "subject_id", null: false
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["goal_id"], name: "index_topics_on_goal_id"
    t.index ["parent_id"], name: "index_topics_on_parent_id"
    t.index ["subject_id"], name: "index_topics_on_subject_id"
  end

  create_table "trip_comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["trip_id"], name: "index_trip_comments_on_trip_id"
    t.index ["user_id"], name: "index_trip_comments_on_user_id"
  end

  create_table "trip_legs", force: :cascade do |t|
    t.string "booking_status", default: "planned", null: false
    t.string "carrier"
    t.string "confirmation_code"
    t.integer "cost_cents"
    t.datetime "created_at", null: false
    t.datetime "departs_at"
    t.string "destination"
    t.date "ends_on"
    t.string "kind", default: "flight", null: false
    t.text "notes"
    t.string "origin"
    t.date "starts_on", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["trip_id", "starts_on"], name: "index_trip_legs_on_trip_id_and_starts_on"
    t.index ["trip_id"], name: "index_trip_legs_on_trip_id"
  end

  create_table "trip_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["trip_id", "user_id"], name: "index_trip_memberships_on_trip_id_and_user_id", unique: true
    t.index ["trip_id"], name: "index_trip_memberships_on_trip_id"
    t.index ["user_id"], name: "index_trip_memberships_on_user_id"
  end

  create_table "trip_photos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "photo_id", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["photo_id"], name: "index_trip_photos_on_photo_id"
    t.index ["trip_id", "photo_id"], name: "index_trip_photos_on_trip_id_and_photo_id", unique: true
    t.index ["trip_id"], name: "index_trip_photos_on_trip_id"
    t.index ["user_id"], name: "index_trip_photos_on_user_id"
  end

  create_table "trips", force: :cascade do |t|
    t.integer "cover_photo_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "east", precision: 10, scale: 6
    t.date "ends_on", null: false
    t.string "name", null: false
    t.decimal "north", precision: 10, scale: 6
    t.string "place_label"
    t.decimal "south", precision: 10, scale: 6
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.decimal "west", precision: 10, scale: 6
    t.index ["user_id", "starts_on"], name: "index_trips_on_user_id_and_starts_on"
    t.index ["user_id"], name: "index_trips_on_user_id"
  end

  create_table "user_sections", force: :cascade do |t|
    t.string "agent_level", default: "quiet", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "position"
    t.integer "section_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["section_id"], name: "index_user_sections_on_section_id"
    t.index ["user_id", "section_id"], name: "index_user_sections_on_user_id_and_section_id", unique: true
    t.index ["user_id"], name: "index_user_sections_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.text "causes_brief"
    t.boolean "celebrations", default: true, null: false
    t.datetime "created_at", null: false
    t.text "digest"
    t.datetime "digest_generated_at"
    t.string "email_address", null: false
    t.string "employer"
    t.json "hidden_vault_pages", default: [], null: false
    t.integer "household_id", null: false
    t.string "job_title"
    t.json "mail_digest"
    t.date "mail_digest_generated_on"
    t.integer "mail_digest_hour", default: 8, null: false
    t.boolean "mail_digest_notify", default: false, null: false
    t.string "measurement_system", default: "imperial", null: false
    t.string "name", null: false
    t.datetime "onboarded_at"
    t.string "password_digest", null: false
    t.boolean "prepare_work", default: true, null: false
    t.text "radar_brief"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["household_id"], name: "index_users_on_household_id"
  end

  create_table "vault_events", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id", null: false
    t.datetime "created_at", null: false
    t.integer "subject_id"
    t.string "subject_type"
    t.integer "subject_user_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["actor_id"], name: "index_vault_events_on_actor_id"
    t.index ["subject_type", "subject_id"], name: "index_vault_events_on_subject_type_and_subject_id"
    t.index ["subject_user_id"], name: "index_vault_events_on_subject_user_id"
    t.index ["user_id", "created_at"], name: "index_vault_events_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_vault_events_on_user_id"
  end

  add_foreign_key "access_grants", "users", column: "grantee_id"
  add_foreign_key "access_grants", "users", column: "grantor_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "album_photos", "albums"
  add_foreign_key "album_photos", "photos"
  add_foreign_key "albums", "photos", column: "cover_photo_id", on_delete: :nullify
  add_foreign_key "albums", "users"
  add_foreign_key "app_errors", "users"
  add_foreign_key "budget_categories", "users"
  add_foreign_key "care_settings", "users"
  add_foreign_key "credential_keys", "credentials"
  add_foreign_key "credential_keys", "users"
  add_foreign_key "credentials", "users"
  add_foreign_key "diary_entries", "users"
  add_foreign_key "diary_entry_keys", "diary_entries"
  add_foreign_key "diary_entry_keys", "users"
  add_foreign_key "diary_imports", "users"
  add_foreign_key "diary_revisions", "diary_entries"
  add_foreign_key "diary_settings", "users"
  add_foreign_key "document_items", "documents"
  add_foreign_key "documents", "users"
  add_foreign_key "email_sender_rules", "users"
  add_foreign_key "emergency_contacts", "users"
  add_foreign_key "emergency_contacts", "users", column: "contact_user_id"
  add_foreign_key "events", "goals"
  add_foreign_key "events", "users"
  add_foreign_key "feed_items", "feeds"
  add_foreign_key "feeds", "users"
  add_foreign_key "goals", "users"
  add_foreign_key "happening_matches", "happenings"
  add_foreign_key "happening_matches", "sections"
  add_foreign_key "happenings", "events"
  add_foreign_key "happenings", "listing_sources"
  add_foreign_key "happenings", "tasks"
  add_foreign_key "hobby_briefs", "sections"
  add_foreign_key "hobby_briefs", "users"
  add_foreign_key "invitations", "households"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "job_feeds", "users"
  add_foreign_key "keyrings", "users"
  add_foreign_key "linked_accounts", "users"
  add_foreign_key "listing_sources", "places"
  add_foreign_key "model_profiles", "households"
  add_foreign_key "notes", "users"
  add_foreign_key "notification_channels", "users"
  add_foreign_key "people", "users"
  add_foreign_key "people", "users", column: "linked_user_id"
  add_foreign_key "pet_foods", "pets"
  add_foreign_key "pet_vaccinations", "documents", on_delete: :nullify
  add_foreign_key "pet_vaccinations", "events", on_delete: :nullify
  add_foreign_key "pet_vaccinations", "people", column: "vet_id", on_delete: :nullify
  add_foreign_key "pet_vaccinations", "pets"
  add_foreign_key "pet_vaccinations", "users", on_delete: :nullify
  add_foreign_key "pets", "people", column: "vet_id"
  add_foreign_key "pets", "sections"
  add_foreign_key "pets", "users"
  add_foreign_key "photo_people", "people"
  add_foreign_key "photo_people", "photos"
  add_foreign_key "photos", "users"
  add_foreign_key "places", "users"
  add_foreign_key "recipe_book_entries", "recipe_books"
  add_foreign_key "recipe_book_entries", "recipes"
  add_foreign_key "recipe_books", "recipes", column: "cover_recipe_id", on_delete: :nullify
  add_foreign_key "recipe_books", "users"
  add_foreign_key "recipe_ingredients", "recipes"
  add_foreign_key "recipes", "users"
  add_foreign_key "reminders", "users"
  add_foreign_key "review_items", "topics"
  add_foreign_key "review_items", "users"
  add_foreign_key "section_taggings", "sections"
  add_foreign_key "sections", "sections", column: "parent_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "share_links", "users"
  add_foreign_key "spending_accounts", "users"
  add_foreign_key "spending_rules", "budget_categories"
  add_foreign_key "spending_rules", "users"
  add_foreign_key "spotted_hobbies", "users"
  add_foreign_key "stays", "trips"
  add_foreign_key "story_routings", "feed_items"
  add_foreign_key "story_routings", "sections"
  add_foreign_key "study_logs", "subjects"
  add_foreign_key "study_logs", "topics"
  add_foreign_key "study_logs", "users"
  add_foreign_key "subjects", "users"
  add_foreign_key "suggestions", "tool_runs", on_delete: :nullify
  add_foreign_key "suggestions", "users"
  add_foreign_key "tasks", "goals"
  add_foreign_key "tasks", "users"
  add_foreign_key "tool_run_items", "tool_runs"
  add_foreign_key "tool_run_messages", "tool_runs"
  add_foreign_key "tool_runs", "users"
  add_foreign_key "topics", "goals"
  add_foreign_key "topics", "subjects"
  add_foreign_key "topics", "topics", column: "parent_id"
  add_foreign_key "trip_comments", "trips"
  add_foreign_key "trip_comments", "users"
  add_foreign_key "trip_legs", "trips"
  add_foreign_key "trip_memberships", "trips"
  add_foreign_key "trip_memberships", "users"
  add_foreign_key "trip_photos", "photos"
  add_foreign_key "trip_photos", "trips"
  add_foreign_key "trip_photos", "users"
  add_foreign_key "trips", "users"
  add_foreign_key "user_sections", "sections"
  add_foreign_key "user_sections", "users"
  add_foreign_key "users", "households"
  add_foreign_key "vault_events", "users"
  add_foreign_key "vault_events", "users", column: "actor_id"
  add_foreign_key "vault_events", "users", column: "subject_user_id"
end
