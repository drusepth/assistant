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

ActiveRecord::Schema[8.1].define(version: 2026_08_26_184147) do
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

  create_table "documents", force: :cascade do |t|
    t.string "analysis_error"
    t.string "analysis_status"
    t.datetime "created_at", null: false
    t.text "description"
    t.json "extracted_facts", default: {}, null: false
    t.text "extracted_text"
    t.boolean "health_plan"
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
    t.datetime "saved_at"
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["feed_id", "guid"], name: "index_feed_items_on_feed_id_and_guid", unique: true
    t.index ["feed_id", "published_at"], name: "index_feed_items_on_feed_id_and_published_at"
    t.index ["feed_id"], name: "index_feed_items_on_feed_id"
    t.index ["read_at"], name: "index_feed_items_on_read_at"
    t.index ["saved_at"], name: "index_feed_items_on_saved_at"
  end

  create_table "feeds", force: :cascade do |t|
    t.boolean "active", default: true, null: false
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
    t.integer "status", default: 1, null: false
    t.date "target_on"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_goals_on_user_id"
  end

  create_table "households", force: :cascade do |t|
    t.text "address"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.string "home_status"
    t.date "moved_in_on"
    t.string "name", null: false
    t.string "phone"
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
    t.string "kind"
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
    t.string "relationship"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["linked_user_id"], name: "index_people_on_linked_user_id"
    t.index ["user_id"], name: "index_people_on_user_id"
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
    t.integer "lead_minutes"
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
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "watcher_slug", null: false
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

  create_table "trips", force: :cascade do |t|
    t.integer "cover_photo_id"
    t.datetime "created_at", null: false
    t.decimal "east", precision: 10, scale: 6, null: false
    t.date "ends_on", null: false
    t.string "name", null: false
    t.decimal "north", precision: 10, scale: 6, null: false
    t.string "place_label"
    t.decimal "south", precision: 10, scale: 6, null: false
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.decimal "west", precision: 10, scale: 6, null: false
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
    t.boolean "celebrations", default: true, null: false
    t.datetime "created_at", null: false
    t.text "digest"
    t.datetime "digest_generated_at"
    t.string "email_address", null: false
    t.string "employer"
    t.integer "household_id", null: false
    t.string "job_title"
    t.json "mail_digest"
    t.date "mail_digest_generated_on"
    t.integer "mail_digest_hour", default: 8, null: false
    t.boolean "mail_digest_notify", default: false, null: false
    t.string "name", null: false
    t.datetime "onboarded_at"
    t.string "password_digest", null: false
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
  add_foreign_key "documents", "users"
  add_foreign_key "email_sender_rules", "users"
  add_foreign_key "emergency_contacts", "users"
  add_foreign_key "emergency_contacts", "users", column: "contact_user_id"
  add_foreign_key "events", "goals"
  add_foreign_key "events", "users"
  add_foreign_key "feed_items", "feeds"
  add_foreign_key "feeds", "users"
  add_foreign_key "goals", "users"
  add_foreign_key "invitations", "households"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "job_feeds", "users"
  add_foreign_key "keyrings", "users"
  add_foreign_key "linked_accounts", "users"
  add_foreign_key "model_profiles", "households"
  add_foreign_key "notes", "users"
  add_foreign_key "notification_channels", "users"
  add_foreign_key "people", "users"
  add_foreign_key "people", "users", column: "linked_user_id"
  add_foreign_key "photo_people", "people"
  add_foreign_key "photo_people", "photos"
  add_foreign_key "photos", "users"
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
  add_foreign_key "study_logs", "subjects"
  add_foreign_key "study_logs", "topics"
  add_foreign_key "study_logs", "users"
  add_foreign_key "subjects", "users"
  add_foreign_key "suggestions", "users"
  add_foreign_key "tasks", "goals"
  add_foreign_key "tasks", "users"
  add_foreign_key "tool_run_items", "tool_runs"
  add_foreign_key "tool_run_messages", "tool_runs"
  add_foreign_key "tool_runs", "users"
  add_foreign_key "topics", "goals"
  add_foreign_key "topics", "subjects"
  add_foreign_key "topics", "topics", column: "parent_id"
  add_foreign_key "trips", "users"
  add_foreign_key "user_sections", "sections"
  add_foreign_key "user_sections", "users"
  add_foreign_key "users", "households"
  add_foreign_key "vault_events", "users"
  add_foreign_key "vault_events", "users", column: "actor_id"
  add_foreign_key "vault_events", "users", column: "subject_user_id"
end
