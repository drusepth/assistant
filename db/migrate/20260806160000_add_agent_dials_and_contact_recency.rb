class AddAgentDialsAndContactRecency < ActiveRecord::Migration[8.1]
  def change
    # D20 dials: per-section agent level. Rows are lazy (absence = Quiet).
    add_column :user_sections, :agent_level, :string, null: false, default: "quiet"
    # Q8: the stay-in-touch signal — set by the person page's "Log contact"
    # button. Deliberately manual: the app can't see your texts, and
    # shouldn't pretend to.
    add_column :people, :last_contacted_on, :date
  end
end
