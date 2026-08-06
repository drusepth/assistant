class EncryptApiKeysAndAddOnboarding < ActiveRecord::Migration[8.1]
  def up
    # Re-save plaintext api_keys through the new encryption (no-op on fresh
    # installs; support_unencrypted_data keeps mixed states readable).
    ModelProfile.reset_column_information
    ModelProfile.find_each(&:encrypt)

    # Existing users have been using the app all along — only accounts
    # created after this migration walk the first-run flow.
    add_column :users, :onboarded_at, :datetime
    User.reset_column_information
    User.update_all(onboarded_at: Time.current)
  end

  def down
    remove_column :users, :onboarded_at
  end
end
