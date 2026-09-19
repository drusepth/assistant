class AddRuleToReminders < ActiveRecord::Migration[8.1]
  def change
    add_column :reminders, :rule, :string
    add_column :reminders, :last_delivered_at, :datetime
  end
end
