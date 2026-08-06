require "test_helper"

class ToolRunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @document = users(:one).documents.create!(title: "Hospital bill", extracted_text: "Amount due: $2,400.")
  end

  test "new renders the tool's form with the user's documents to pick from" do
    get new_tool_run_path("dispute_letter")

    assert_response :success
    assert_match "Draft a dispute letter", response.body
    assert_match "Hospital bill", response.body
  end

  test "new 404s for an unknown tool" do
    get new_tool_run_path("nonsense")
    assert_response :not_found
  end

  test "a hobby input is a free-text field until lenses exist, then a picker" do
    get new_tool_run_path("find_your_people")
    assert_response :success
    assert_select "input[type=text]#inputs_hobby"

    Hobbies::Lens.find_or_create!("Guitar")
    get new_tool_run_path("find_your_people")
    assert_select "select#inputs_hobby option", "Guitar"
  end

  test "create enqueues the run and lands on its page" do
    assert_enqueued_with job: ToolRunJob do
      post run_tool_path("dispute_letter"), params: { inputs: { document_id: @document.id, intent: "remove the charge" } }
    end

    run = users(:one).tool_runs.last
    assert_redirected_to tool_run_path(run)
    assert_equal "dispute_letter", run.tool_slug
    assert_equal @document.id.to_s, run.inputs["document_id"]
  end

  test "create without the required document re-renders the form" do
    assert_no_enqueued_jobs do
      post run_tool_path("dispute_letter"), params: { inputs: { intent: "fix it" } }
    end

    assert_response :unprocessable_entity
    assert_match "needs an answer", response.body
  end

  test "show is only visible to the run's owner" do
    run = users(:one).tool_runs.create!(tool_slug: "dispute_letter", inputs: { "document_id" => @document.id.to_s })

    get tool_run_path(run)
    assert_response :success

    sign_in_as users(:two)
    get tool_run_path(run)
    assert_response :not_found
  end

  test "show renders a finished run's drafts and follow-ups" do
    run = users(:one).tool_runs.create!(tool_slug: "dispute_letter", inputs: { "document_id" => @document.id.to_s })
    note = users(:one).notes.create!(title: "Dispute of account 12345", body: "To whom it may concern")
    task = users(:one).tasks.create!(title: "Mail the letter")
    run.tool_run_items.create!(item: note)
    run.tool_run_items.create!(item: task)
    run.update!(status: :done)

    get tool_run_path(run)

    assert_response :success
    assert_match "To whom it may concern", response.body
    assert_match "Mail the letter", response.body
    assert_match "never sends anything on your behalf", response.body
  end
end
