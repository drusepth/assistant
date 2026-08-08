require "test_helper"

# Applications die of silence: a quiet application task earns a follow-up
# nudge whose accept creates the follow-up task — capped, monthly-bucketed.
class ApplicationFollowUpWatcherTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "a quiet application task earns a follow-up nudge" do
    task = application_task("Apply: Acme shift lead")

    suggestion = scan.sole
    assert_equal "application_follow_up/task:#{task.id}/#{Date.current.strftime("%Y-%m")}", suggestion.fingerprint
    assert_includes suggestion.title, "Apply: Acme shift lead"
    assert_equal({ "task" => { "title" => "Follow up on: Apply: Acme shift lead" } }, suggestion.action)
    assert_equal [ sections(:career) ], suggestion.sections.to_a
  end

  test "fresh, completed, and non-application career tasks stay quiet" do
    @user.tasks.create!(title: "Apply: fresh one").tap { |t| t.sections = [ sections(:career) ] }
    application_task("Apply: done one").update_columns(completed_at: Time.current)
    application_task("Update the resume note")

    assert_empty scan
  end

  test "an application task outside Career is not this watcher's beat" do
    task = @user.tasks.create!(title: "Apply for the parking permit")
    task.update_columns(updated_at: 3.weeks.ago)

    assert_empty scan
  end

  test "at most three live nudges at a time" do
    5.times { |i| application_task("Apply: employer #{i}", age: (20 - i).days) }

    assert_equal 3, scan.count
    assert_no_difference "Suggestion.count" do
      Watcher::ApplicationFollowUp.new(@user).scan
    end
  end

  private
    def application_task(title, age: 2.weeks)
      task = @user.tasks.create!(title: title)
      task.sections = [ sections(:career) ]
      task.update_columns(updated_at: age.ago)
      task
    end

    def scan
      Watcher::ApplicationFollowUp.new(@user).scan
      @user.suggestions.pending.order(:id).to_a
    end
end
