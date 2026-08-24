# An item you can ask to be reminded about (D-reminders). Mixed into the
# dated primitives — Event and Task — alongside Sectionable and Visible.
module Remindable
  extend ActiveSupport::Concern

  # When an item's own date carries no time of day (an all-day event, a
  # task due on a date), this is the hour a relative reminder counts back
  # from. Counting back from midnight would ping the night before.
  DAY_START_HOUR = 9

  included do
    has_many :reminders, as: :subject, dependent: :destroy

    # A relative reminder follows the item it hangs on. Without this,
    # "an hour before" becomes a lie the moment an appointment moves —
    # and one reminder that fires at the old time is enough to stop
    # someone trusting the feature.
    after_update_commit :resync_reminders
  end

  # The moment a relative reminder counts back from; nil when the item has
  # no date to hang one on, which leaves it absolute-only.
  def remind_from = nil

  private
    def resync_reminders
      reminders.relative.each(&:resync!)
    end
end
