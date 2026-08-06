require "test_helper"

class AppErrorTest < ActiveSupport::TestCase
  test "records the shape of a failure" do
    error = Llm::Error.new("Rate limit reached")
    error.set_backtrace([ "line one", "line two" ])

    recorded = AppError.record(error, source: "CategorizeTaskJob", user: users(:one), context: { task_id: 42 })

    assert_equal "CategorizeTaskJob", recorded.source
    assert_equal "Llm::Error", recorded.error_class
    assert_equal "Rate limit reached", recorded.message
    assert_equal users(:one), recorded.user
    assert_equal({ "task_id" => 42 }, recorded.context)
    assert_equal [ "line one", "line two" ], recorded.backtrace_lines
  end

  test "records without a user or a backtrace" do
    recorded = AppError.record(StandardError.new("boom"), source: "Somewhere")

    assert_nil recorded.user
    assert_nil recorded.backtrace
    assert_empty recorded.context
  end

  test "truncates a runaway message instead of refusing to log it" do
    recorded = AppError.record(StandardError.new("x" * 5000), source: "Somewhere")

    assert_equal AppError::MESSAGE_LIMIT, recorded.message.length
  end

  test "recording a failure never raises one" do
    # A context value that explodes on serialization stands in for anything
    # that can go wrong while writing the row: the job that was only trying to
    # report a problem must not acquire a second one.
    unserializable = Object.new
    def unserializable.as_json(*) = raise("cannot serialize me")

    assert_nothing_raised do
      assert_nil AppError.record(StandardError.new("boom"), source: "Somewhere", context: { thing: unserializable })
    end
  end

  test "prunes to the newest KEPT rows" do
    (AppError::KEPT + 3).times { |i| AppError.record(StandardError.new("error #{i}"), source: "Loop") }

    assert_equal AppError::KEPT, AppError.count
    assert_equal "error #{AppError::KEPT + 2}", AppError.recent.first.message
    assert_not AppError.exists?(message: "error 0")
  end

  test "report is a paste-ready plain-text account of the failure" do
    error = Llm::Error.new("Rate limit reached")
    error.set_backtrace([ "app/services/llm/client.rb:10", "app/jobs/categorize_task_job.rb:11" ])
    recorded = AppError.record(error, source: "CategorizeTaskJob", user: users(:one), context: { task_id: 42 })

    report = recorded.report

    assert_equal "CategorizeTaskJob — Llm::Error", report.lines.first.chomp
    assert_includes report, recorded.created_at.utc.iso8601
    assert_includes report, "user: Alice Smith"
    assert_includes report, "task_id: 42"
    assert_includes report, "Rate limit reached"
    assert_includes report, "app/services/llm/client.rb:10"
  end

  test "report survives a bare error with no user, context, or backtrace" do
    recorded = AppError.record(StandardError.new("boom"), source: "Somewhere")

    assert_equal [ "Somewhere — StandardError", recorded.created_at.utc.iso8601, "boom" ],
                 recorded.report.lines.map(&:chomp)
  end

  test "report_for joins many reports into one pasteable block" do
    first = AppError.record(StandardError.new("first"), source: "A")
    second = AppError.record(StandardError.new("second"), source: "B")

    combined = AppError.report_for([ first, second ])

    assert_includes combined, "first"
    assert_includes combined, "second"
    assert_includes combined, "-" * 40
  end

  test "recent orders newest first" do
    old = AppError.record(StandardError.new("old"), source: "A")
    old.update!(created_at: 2.days.ago)
    fresh = AppError.record(StandardError.new("fresh"), source: "B")

    assert_equal [ fresh, old ], AppError.recent.to_a
  end
end
