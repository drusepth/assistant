require "test_helper"

class ApplicationJobTest < ActiveJob::TestCase
  # Stand-ins for any job with a bug: the error is nobody's rescue clause.
  class ExplodingJob < ApplicationJob
    def perform(*) = raise "boom from a background job"
  end

  class RethrowingJob < ApplicationJob
    def perform(user)
      raise "boom this job handled itself"
    rescue StandardError => e
      record_failure(e, user: user, context: { handled: true })
      raise
    end
  end

  test "an unhandled error is recorded for /admin before reaching the backend" do
    error = assert_raises(RuntimeError) { ExplodingJob.perform_now }
    assert_equal "boom from a background job", error.message

    recorded = AppError.recent.first
    assert_equal "ApplicationJobTest::ExplodingJob", recorded.source
    assert_equal "RuntimeError", recorded.error_class
    assert_equal "boom from a background job", recorded.message
    assert recorded.backtrace.present?, "the backtrace is the part worth pasting"
  end

  test "the failure is attributed to a user argument when there is one" do
    assert_raises(RuntimeError) { ExplodingJob.perform_now(users(:one)) }

    assert_equal users(:one), AppError.recent.first.user
  end

  test "the failure is attributed through a record's owner" do
    task = users(:one).tasks.create!(title: "Doomed")

    assert_raises(RuntimeError) { ExplodingJob.perform_now(task) }

    assert_equal users(:one), AppError.recent.first.user
  end

  test "a job that already recorded its error doesn't record it twice" do
    assert_difference -> { AppError.count }, 1 do
      assert_raises(RuntimeError) { RethrowingJob.perform_now(users(:one)) }
    end

    recorded = AppError.recent.first
    assert_equal({ "handled" => true }, recorded.context, "the job's own richer record wins")
  end

  test "a record deleted before its job runs discards the job quietly" do
    task = users(:one).tasks.create!(title: "Short-lived")
    CategorizeTaskJob.perform_later(task)
    task.destroy!

    assert_nothing_raised { perform_enqueued_jobs }
    assert_equal 0, AppError.count
  end
end
