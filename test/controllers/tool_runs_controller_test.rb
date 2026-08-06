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

  test "new prefills inputs from the query string — the D21 routing entry point" do
    get new_tool_run_path("insurance_appeal", inputs: { document_id: @document.id, intent: "it was an emergency" })

    assert_response :success
    assert_select "select#inputs_document_id option[selected][value='#{@document.id}']"
    assert_select "input#inputs_intent[value='it was an emergency']"
  end

  test "show renders a finished run's suggested next steps as prefilled links" do
    run = users(:one).tool_runs.create!(tool_slug: "decode_letter", inputs: { "document_id" => @document.id.to_s })
    run.update!(status: :done, output: { "next_tools" => [
      { "slug" => "insurance_appeal", "inputs" => { "document_id" => @document.id.to_s }, "reason" => "This denial can be appealed." }
    ] })

    get tool_run_path(run)

    assert_response :success
    assert_match "This denial can be appealed.", response.body
    assert_select "a[href=?]",
      new_tool_run_path("insurance_appeal", inputs: { document_id: @document.id.to_s }),
      text: /Start/
  end

  test "new renders select and checkbox input kinds" do
    get new_tool_run_path("benefits_screener")

    assert_response :success
    assert_select "select#inputs_state option[value='Ohio']"
    assert_select "input[type=checkbox][name='inputs[circumstances][]'][value='Children under 18']"
  end

  test "create keeps checkbox answers as an array" do
    assert_enqueued_with job: ToolRunJob do
      post run_tool_path("benefits_screener"), params: { inputs: {
        state: "Ohio", household_size: "3", monthly_income: "$2,400",
        circumstances: [ "Children under 18", "Renting my home" ]
      } }
    end

    run = users(:one).tool_runs.last
    assert_equal [ "Children under 18", "Renting my home" ], run.inputs["circumstances"]
  end

  test "a chat run's page shows the transcript and the composer" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" })
    run.tool_run_messages.create!(role: :assistant, content: "Where shall we start?")
    run.update!(status: :done)

    get tool_run_path(run)

    assert_response :success
    assert_match "Where shall we start?", response.body
    assert_select "form[action=?]", tool_run_messages_path(run)
    assert_select "form[action=?]", recap_tool_run_path(run)
  end

  test "posting a message stores the turn and enqueues the reply" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)

    assert_enqueued_with job: ChatTurnJob do
      post tool_run_messages_path(run), params: { content: "What is 1/2 + 1/4?" }
    end

    assert_redirected_to tool_run_path(run)
    message = run.tool_run_messages.sole
    assert message.user_role?
    assert_equal "What is 1/2 + 1/4?", message.content
  end

  test "a blank message enqueues nothing" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)

    assert_no_enqueued_jobs do
      post tool_run_messages_path(run), params: { content: "" }
    end
    assert_empty run.tool_run_messages
  end

  test "messages can't be posted to a draft-kind run or someone else's run" do
    draft_run = users(:one).tool_runs.create!(
      tool_slug: "dispute_letter", inputs: { "document_id" => @document.id.to_s }, status: :done
    )
    post tool_run_messages_path(draft_run), params: { content: "hi" }
    assert_response :unprocessable_entity

    chat_run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "x" }, status: :done)
    sign_in_as users(:two)
    post tool_run_messages_path(chat_run), params: { content: "hi" }
    assert_response :not_found
  end

  test "recap enqueues only when there's a conversation to recap" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)

    assert_no_enqueued_jobs { post recap_tool_run_path(run) }

    run.tool_run_messages.create!(role: :assistant, content: "Hi!")
    assert_enqueued_with(job: ChatRecapJob) { post recap_tool_run_path(run) }
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
