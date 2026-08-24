class RemindersController < ApplicationController
  def create
    reminder = Current.user.reminders.new(reminder_attributes)

    if reminder.save
      redirect_back fallback_location: today_path,
        notice: "Reminder set for #{reminder.local_deliver_at.strftime("%a %b %-d at %-l:%M %p")}."
    else
      redirect_back fallback_location: today_path, alert: reminder.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.reminders.find(params[:id]).destroy!
    redirect_back fallback_location: today_path, notice: "Reminder removed."
  end

  private
    # The subject type is allowlisted in the model rather than trusted from
    # the form, and the owner check lives there too — a reminder is
    # delivery, never a way to reach past your own items.
    def reminder_attributes
      permitted = params.expect(reminder: [ :body, :lead_minutes, :deliver_on, :deliver_time, :subject_type, :subject_id ])
      # A blank lead time means the user filled in the exact-time fields
      # instead; leaving "" through would make the reminder relative to
      # nothing and silently ignore the date they picked.
      permitted[:lead_minutes] = permitted[:lead_minutes].presence
      permitted
    end
end
