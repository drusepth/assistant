# The email plan's E0 pass (EMAIL_PLAN.md §10): the linked-account layer
# grows what every consumer after it needs — multiple links per provider,
# encrypted credentials, per-link settings. (The household clock the mail
# digest reads is `households.time_zone`, added by D-household-profile.)
class PlatformPassForMultiLinkAccounts < ActiveRecord::Migration[8.1]
  def up
    # Multi-link providers (email first): one row per mailbox, told apart
    # by a user-facing label. Uniqueness moves to model validations, which
    # can distinguish multi from single-link providers; the index stays
    # for lookups only.
    add_column :linked_accounts, :label, :string
    remove_index :linked_accounts, %i[ user_id provider ]
    add_index :linked_accounts, %i[ user_id provider ]

    # Per-link settings (dials for the email consumer: digest, alerts,
    # AI processing, own addresses, pause, mirror window).
    add_column :linked_accounts, :settings, :json, null: false, default: {}

    # Credentials become encrypted at rest (the pending D26 follow-up):
    # json column -> text, so the model can serialize + encrypt. Existing
    # plaintext JSON stays readable via support_unencrypted_data until the
    # re-save below encrypts it.
    change_column :linked_accounts, :credentials, :text, null: false, default: "{}"
    LinkedAccount.reset_column_information
    LinkedAccount.find_each(&:encrypt)
  end

  def down
    change_column :linked_accounts, :credentials, :json, null: false, default: {}
    remove_column :linked_accounts, :settings
    remove_index :linked_accounts, %i[ user_id provider ]
    add_index :linked_accounts, %i[ user_id provider ], unique: true
    remove_column :linked_accounts, :label
  end
end
