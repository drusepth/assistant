require "test_helper"

# The send click on a Tailor-my-application run: one explicit post sends
# the reviewed message and puts the application on the record.
class ApplicationEmailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    Career::EmailApply.delivery_override = :test
    Mail::TestMailer.deliveries.clear
    @run = users(:one).tool_runs.create!(
      tool_slug: "tailor_application", status: :done,
      inputs: { "role" => "Shift lead at Acme" }
    )
  end

  teardown { Career::EmailApply.delivery_override = nil }

  test "sending logs the Applied event and the follow-up task on the run" do
    assert_difference [ "Event.count", "Task.count" ], 1 do
      post tool_run_application_email_path(@run), params: {
        to: "jobs@acme.com", subject: "Application — Shift lead", body: "Dear hiring manager…"
      }
    end

    assert_redirected_to @run
    assert_equal 1, Mail::TestMailer.deliveries.size

    event = users(:one).events.order(:id).last
    assert_equal "Applied: Shift lead at Acme", event.title
    assert_equal [ sections(:career) ], event.sections.to_a

    task = users(:one).tasks.order(:id).last
    assert_equal "Follow up on application: Shift lead at Acme", task.title
    assert_equal 10.days.from_now.to_date, task.due_on

    assert_equal [ event, task ].to_set, @run.reload.items.to_set - @run.items.grep(Note).to_set
  end

  test "a send failure explains and logs nothing" do
    linked_accounts(:alice_email).update!(disabled_scopes: [ "send" ])

    assert_no_difference [ "Event.count", "Task.count" ] do
      post tool_run_application_email_path(@run), params: { to: "jobs@acme.com", subject: "s", body: "b" }
    end

    assert_redirected_to @run
    assert_match(/switched off/, flash[:alert])
    assert_empty Mail::TestMailer.deliveries
  end

  test "another user's run is unreachable" do
    other = users(:two).tool_runs.create!(tool_slug: "tailor_application", status: :done,
      inputs: { "role" => "Their role", "listing" => "x" })

    post tool_run_application_email_path(other), params: { to: "jobs@acme.com", subject: "s", body: "b" }
    assert_response :not_found
    assert_empty Mail::TestMailer.deliveries
  end
end
