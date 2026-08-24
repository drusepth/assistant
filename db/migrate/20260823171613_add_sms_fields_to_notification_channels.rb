class AddSmsFieldsToNotificationChannels < ActiveRecord::Migration[8.1]
  def change
    # Provider credentials live apart from `config` so they can be encrypted
    # at rest the way linked_accounts.credentials is — `config` stays plain
    # JSON that Settings can render back to the user.
    add_column :notification_channels, :secrets, :text, default: "{}", null: false

    # SMS is the first channel that costs money per message, so every send
    # is metered against a per-channel daily cap.
    add_column :notification_channels, :sent_on, :date
    add_column :notification_channels, :sent_count, :integer, default: 0, null: false
  end
end
