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

ActiveRecord::Schema[8.1].define(version: 2026_08_06_190000) do
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

  create_table "documents", force: :cascade do |t|
    t.string "analysis_error"
    t.string "analysis_status"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "extracted_text"
    t.json "suggested_sections", default: []
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_documents_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.boolean "all_day", default: false, null: false
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
    t.datetime "created_at", null: false
    t.string "name", null: false
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

  create_table "linked_accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "credentials", default: {}, null: false
    t.json "disabled_scopes", default: [], null: false
    t.string "provider", null: false
    t.string "sync_error"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "provider"], name: "index_linked_accounts_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_linked_accounts_on_user_id"
  end

  create_table "model_profiles", force: :cascade do |t|
    t.string "api_key"
    t.string "base_url", default: "https://api.openai.com/v1", null: false
    t.datetime "created_at", null: false
    t.integer "household_id", null: false
    t.string "model", default: "gpt-4o-mini"
    t.string "provider", default: "openai", null: false
    t.datetime "updated_at", null: false
    t.index ["household_id"], name: "index_model_profiles_on_household_id", unique: true
  end

  create_table "notes", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "people", force: :cascade do |t|
    t.text "address"
    t.date "birthday"
    t.datetime "created_at", null: false
    t.string "email"
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
    t.text "notes"
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

  create_table "tool_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "error"
    t.json "inputs", default: {}, null: false
    t.json "output", default: {}, null: false
    t.string "status", default: "queued", null: false
    t.string "tool_slug", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_tool_runs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_tool_runs_on_user_id"
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
    t.datetime "created_at", null: false
    t.text "digest"
    t.datetime "digest_generated_at"
    t.string "email_address", null: false
    t.integer "household_id", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["household_id"], name: "index_users_on_household_id"
  end

  add_foreign_key "access_grants", "users", column: "grantee_id"
  add_foreign_key "access_grants", "users", column: "grantor_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "documents", "users"
  add_foreign_key "events", "goals"
  add_foreign_key "events", "users"
  add_foreign_key "goals", "users"
  add_foreign_key "invitations", "households"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "linked_accounts", "users"
  add_foreign_key "model_profiles", "households"
  add_foreign_key "notes", "users"
  add_foreign_key "people", "users"
  add_foreign_key "people", "users", column: "linked_user_id"
  add_foreign_key "section_taggings", "sections"
  add_foreign_key "sections", "sections", column: "parent_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "suggestions", "users"
  add_foreign_key "tasks", "goals"
  add_foreign_key "tasks", "users"
  add_foreign_key "tool_run_items", "tool_runs"
  add_foreign_key "tool_runs", "users"
  add_foreign_key "user_sections", "sections"
  add_foreign_key "user_sections", "users"
  add_foreign_key "users", "households"
end
