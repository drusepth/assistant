require "test_helper"

class Admin::ErrorsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "lists recorded errors newest first" do
    AppError.record(StandardError.new("older failure"), source: "AnalyzeDocumentJob")
    AppError.record(StandardError.new("newer failure"), source: "ToolRunJob")

    get admin_errors_path

    assert_response :success
    assert_match "older failure", response.body
    assert_match "newer failure", response.body
    assert_operator response.body.index("newer failure"), :<, response.body.index("older failure")
  end

  test "every error is copyable, together and one at a time" do
    error = StandardError.new("copy me")
    error.set_backtrace([ "app/jobs/somewhere.rb:1" ])
    AppError.record(error, source: "ToolRunJob")

    get admin_errors_path

    assert_response :success
    assert_select "[data-controller=clipboard] [data-action='clipboard#copy']", minimum: 2
    assert_match "Copy all", response.body
    assert_match "app/jobs/somewhere.rb:1", response.body, "the backtrace is on the page"
  end

  test "shows an empty state with no errors" do
    get admin_errors_path

    assert_response :success
    assert_match "No errors recorded", response.body
  end

  test "clearing empties the log" do
    AppError.record(StandardError.new("boom"), source: "ToolRunJob")

    delete destroy_all_admin_errors_path

    assert_redirected_to admin_errors_path
    assert_equal 0, AppError.count
  end

  test "a non-admin can neither read nor clear the log" do
    sign_out
    sign_in_as users(:two)
    AppError.record(StandardError.new("boom"), source: "ToolRunJob")

    get admin_errors_path
    assert_redirected_to settings_path

    delete destroy_all_admin_errors_path
    assert_redirected_to settings_path
    assert_equal 1, AppError.count
  end
end
