class RemindersController < ApplicationController
  def create
    reminder = Current.user.reminders.new(reminder_attributes)

    if reminder.save
      redirect_back fallback_location: today_path, notice: "Reminder set #{when_phrase(reminder)}."
    else
      redirect_back fallback_location: today_path, alert: reminder.errors.full_messages.to_sentence
    end
  end

  def update
    reminder = Current.user.reminders.find(params[:id])

    if reminder.update(reminder_attributes)
      redirect_back fallback_location: today_path, notice: "Reminder changed — now #{when_phrase(reminder)}."
    else
      redirect_back fallback_location: today_path, alert: reminder.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.reminders.find(params[:id]).destroy!
    redirect_back fallback_location: today_path, notice: "Reminder removed."
  end

  # Plain words into the form (D-standing-reminders): the model reads the
  # sentence and the form comes back prefilled for the user to check and
  # send. Nothing is saved here — the click on "Remind me" is still the
  # only write (D20). Off, and said so in the view, without a model.
  def parse
    profile = Current.user.household.model_profile
    text = params[:text].to_s.strip
    raise Llm::Error, "No model is set up." unless profile&.configured?
    raise Llm::Error, "Say what to remind you of." if text.blank?

    parsed = Reminders::Parse.new(text: text, profile: profile, zone: Current.user.household.zone).call
    reminder = Current.user.reminders.new(parsed.attributes)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("new_reminder", partial: "reminders/form",
            locals: { reminder: reminder, subject: nil, show_body: true }),
          turbo_stream.replace("reminder_capture", partial: "reminders/capture", locals: { text: "", filled: true })
        ]
      end
      format.html { redirect_to today_path, alert: "Turn on JavaScript to fill the form from plain words, or fill it in below." }
    end
  rescue Llm::Error => error
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("reminder_capture", partial: "reminders/capture",
          locals: { text: text, error: "Couldn't make that out — #{error.message.chomp('.')}. The form below still works." })
      end
      format.html { redirect_to today_path, alert: error.message }
    end
  end

  private
    # The subject type is allowlisted in the model rather than trusted from
    # the form, and the owner check lives there too — a reminder is
    # delivery, never a way to reach past your own items.
    def reminder_attributes
      permitted = params.expect(reminder: [ :body, :lead_minutes, :deliver_on, :deliver_time, :subject_type, :subject_id,
                                            :repeat, :repeat_until, repeat_days: [] ])
      # A blank lead time means the user filled in the exact-time fields
      # instead; leaving "" through would make the reminder relative to
      # nothing and silently ignore the date they picked.
      permitted[:lead_minutes] = permitted[:lead_minutes].presence
      permitted[:repeat_until] = permitted[:repeat_until].presence if permitted.key?(:repeat_until)
      permitted
    end

    # "for Thu Sep 24 at 8:00 PM", or "weekly on Thursday, next Thu Sep 24 at
    # 8:00 PM" — the flash is where a standing reminder confirms the day it
    # landed on, since the picked date was only where the series starts.
    def when_phrase(reminder)
      moment = reminder.local_deliver_at.strftime("%a %b %-d at %-l:%M %p")
      reminder.standing? ? "#{reminder.cadence}, next #{moment}" : "for #{moment}"
    end
end
