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

ActiveRecord::Schema[8.1].define(version: 2026_08_08_081209) do
  create_table "email_folders", force: :cascade do |t|
    t.datetime "backfilled_at"
    t.datetime "created_at", null: false
    t.integer "last_seen_uid", default: 0, null: false
    t.integer "linked_account_id", null: false
    t.string "name", null: false
    t.string "role", default: "other", null: false
    t.integer "uidvalidity"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["linked_account_id", "name"], name: "index_email_folders_on_linked_account_id_and_name", unique: true
    t.index ["user_id"], name: "index_email_folders_on_user_id"
  end

  create_table "email_message_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "email_message_id", null: false
    t.integer "item_id", null: false
    t.string "item_type", null: false
    t.datetime "updated_at", null: false
    t.index ["email_message_id"], name: "index_email_message_items_on_email_message_id"
  end

  create_table "email_messages", force: :cascade do |t|
    t.datetime "alerted_at"
    t.boolean "answered", default: false, null: false
    t.json "attachments", default: [], null: false
    t.boolean "backfilled", default: false, null: false
    t.text "body_text"
    t.boolean "bulk", default: false, null: false
    t.json "cc_emails", default: [], null: false
    t.datetime "created_at", null: false
    t.string "direction", default: "inbound", null: false
    t.integer "email_folder_id", null: false
    t.boolean "expects_reply"
    t.string "from_email"
    t.string "from_name"
    t.integer "importance"
    t.integer "linked_account_id", null: false
    t.string "message_id", null: false
    t.integer "person_id"
    t.date "reply_wanted_by"
    t.boolean "seen", default: false, null: false
    t.datetime "sent_at"
    t.string "snippet"
    t.string "subject"
    t.string "thread_key", null: false
    t.json "to_emails", default: [], null: false
    t.json "triage"
    t.datetime "triaged_at"
    t.integer "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["email_folder_id"], name: "index_email_messages_on_email_folder_id"
    t.index ["linked_account_id", "message_id"], name: "index_email_messages_on_linked_account_id_and_message_id", unique: true
    t.index ["person_id"], name: "index_email_messages_on_person_id"
    t.index ["user_id", "importance"], name: "index_email_messages_on_user_id_and_importance"
    t.index ["user_id", "sent_at"], name: "index_email_messages_on_user_id_and_sent_at"
    t.index ["user_id", "thread_key"], name: "index_email_messages_on_user_id_and_thread_key"
  end

  create_table "email_tombstones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "linked_account_id", null: false
    t.string "message_id", null: false
    t.datetime "updated_at", null: false
    t.index ["linked_account_id", "message_id"], name: "index_email_tombstones_on_linked_account_id_and_message_id", unique: true
  end

  create_table "spending_tombstones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.integer "spending_account_id", null: false
    t.datetime "updated_at", null: false
    t.index ["spending_account_id", "fingerprint"], name: "idx_on_spending_account_id_fingerprint_722346f124", unique: true
  end

  create_table "spending_transactions", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.integer "budget_category_id"
    t.string "categorized_by"
    t.datetime "created_at", null: false
    t.string "descriptor"
    t.integer "document_id"
    t.string "external_id"
    t.string "fingerprint", null: false
    t.string "merchant"
    t.date "occurred_on", null: false
    t.string "source", default: "statement", null: false
    t.integer "spending_account_id", null: false
    t.boolean "transfer", default: false, null: false
    t.string "transfer_set_by"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["spending_account_id", "external_id"], name: "idx_on_spending_account_id_external_id_383ab3ba83"
    t.index ["spending_account_id", "fingerprint"], name: "idx_on_spending_account_id_fingerprint_fdfe06a3c2", unique: true
    t.index ["user_id", "budget_category_id"], name: "index_spending_transactions_on_user_id_and_budget_category_id"
    t.index ["user_id", "merchant"], name: "index_spending_transactions_on_user_id_and_merchant"
    t.index ["user_id", "occurred_on"], name: "index_spending_transactions_on_user_id_and_occurred_on"
  end
end
