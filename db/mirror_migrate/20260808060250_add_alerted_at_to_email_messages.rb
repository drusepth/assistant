# Urgent alerts (E3): when a message rang a phone — the cap and the
# one-alert-per-thread rule query this.
class AddAlertedAtToEmailMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :email_messages, :alerted_at, :datetime
  end
end
