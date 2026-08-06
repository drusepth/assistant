require "test_helper"

class Admin::FailedJobsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  # Solid Queue's tables exist only in production, so these exercise the
  # graceful path: every action lands back on /admin with an honest notice
  # rather than crashing on the missing queue database.
  test "retrying a failure that isn't there redirects with a notice" do
    post retry_admin_failed_job_path(1)

    assert_redirected_to admin_root_path
    assert_equal "That failed job is no longer there.", flash[:notice]
  end

  test "discarding a failure that isn't there redirects with a notice" do
    delete discard_admin_failed_job_path(1)

    assert_redirected_to admin_root_path
    assert_equal "That failed job is no longer there.", flash[:notice]
  end

  test "discarding all without a queue backend redirects with a notice" do
    delete discard_all_admin_failed_jobs_path

    assert_redirected_to admin_root_path
    assert_equal "The job backend isn't available.", flash[:notice]
  end

  test "a non-admin cannot touch failed jobs" do
    sign_out
    sign_in_as users(:two)

    post retry_admin_failed_job_path(1)
    assert_redirected_to settings_path

    delete discard_all_admin_failed_jobs_path
    assert_redirected_to settings_path
  end
end
