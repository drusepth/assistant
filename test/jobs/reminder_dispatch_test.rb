require "test_helper"

# D-reminders: the delivery half. A reminder fires once, at its moment,
# through whatever channels the user set up — and unlike everything else
# that reaches a phone, it does not consult the agent dials.
class ReminderDispatchTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    @user.notification_channels.create!(kind: :webhook, config: { "url" => "https://ntfy.example/topic" })
    @hook = stub_request(:post, "https://ntfy.example/topic")
  end

  test "a due reminder fires and is marked delivered" do
    reminder = due_reminder("Call the pharmacy")

    perform_enqueued_jobs { Reminders::DispatchJob.dispatch_due }

    assert_requested(:post, "https://ntfy.example/topic") do |request|
      JSON.parse(request.body)["message"] == "Reminder: Call the pharmacy"
    end
    assert_not_nil reminder.reload.delivered_at
  end

  test "a reminder that is not due yet stays quiet" do
    @user.reminders.create!(body: "Later", deliver_on: Date.current + 1, deliver_time: "23:00")

    perform_enqueued_jobs { Reminders::DispatchJob.dispatch_due }

    assert_not_requested @hook
  end

  test "a reminder fires exactly once even if the dispatcher runs again first" do
    due_reminder("Call the pharmacy")

    perform_enqueued_jobs do
      Reminders::DispatchJob.dispatch_due
      Reminders::DispatchJob.dispatch_due
    end

    assert_requested @hook, times: 1
  end

  test "a reminder that missed its moment by a day is retired, not delivered" do
    reminder = due_reminder("The box was off", at: 3.days.ago)

    perform_enqueued_jobs { Reminders::DispatchJob.dispatch_due }

    assert_not_requested @hook
    assert_not_nil reminder.reload.delivered_at, "retired so it never comes back"
  end

  test "a reminder ignores the section dials that gate the agent" do
    # Every section is Quiet by default, which silences watcher output
    # entirely (D22) — a reminder the user armed themselves is not that.
    assert_equal "quiet", UserSection::DEFAULT_AGENT_LEVEL
    due_reminder("Call the pharmacy")

    perform_enqueued_jobs { Reminders::DispatchJob.dispatch_due }

    assert_requested @hook, times: 1
  end

  test "a reminder deleted before its job runs is not an error" do
    reminder = due_reminder("Gone")
    Reminders::DispatchJob.dispatch_due
    reminder.destroy!

    assert_nothing_raised { perform_enqueued_jobs }
    assert_not_requested @hook
  end

  test "an SMS channel over its daily cap does not get the reminder either" do
    @user.notification_channels.create!(
      kind: :sms,
      config: { "provider" => "gammu", "outbox_path" => Dir.mktmpdir, "to" => "+15555550123", "daily_limit" => 1 },
      sent_on: Date.current, sent_count: 1
    )
    outbox = @user.notification_channels.sms.sole.config["outbox_path"]
    due_reminder("Call the pharmacy")

    perform_enqueued_jobs { Reminders::DispatchJob.dispatch_due }

    assert_empty Dir.children(outbox), "the cap is the user's stated budget, reminders included"
    # The free channel still fires — the cap is per channel, not per reminder.
    assert_requested @hook, times: 1
  end

  private
    def due_reminder(body, at: 1.minute.ago)
      reminder = @user.reminders.new(body: body, deliver_on: Date.current + 1, deliver_time: "09:00")
      # Past times are rejected on create for the user's sake; the
      # dispatcher's job is what happens once a real one comes due.
      reminder.save!
      reminder.update_columns(deliver_at: at)
      reminder
    end
end
