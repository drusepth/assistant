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

  test "a chat tool's form offers your own recent sessions to pick back up" do
    mine = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)
    bound = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done,
      subject: users(:one).tasks.create!(title: "Bound elsewhere"))
    theirs = users(:two).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)

    get new_tool_run_path("check_in")

    assert_response :success
    assert_select "a[href=?]", tool_run_path(mine)
    assert_select "a[href=?]", tool_run_path(bound), count: 0
    assert_select "a[href=?]", tool_run_path(theirs), count: 0
  end

  test "a one-shot tool's form offers nothing to pick back up" do
    get new_tool_run_path("dispute_letter")

    assert_response :success
    assert_no_match "Pick up where you left off", response.body
  end

  test "a live chat run is a screen, not a page (D-chat-shell)" do
    run = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "How has the week been?")

    get tool_run_path(run)

    assert_response :success
    assert_select ".chat-page .chat-screen"
    # The composer's row is inside the screen, not somewhere below the page.
    assert_select ".chat-screen .composer"
    # Chrome folds into the screen's own bar below lg.
    assert_select ".chat-screen a[aria-label=?]", "Back to your conversations"
    assert_select ".chat-screen [data-popover-target=panel] a", text: "New session"
  end

  test "a chat run that hasn't opened yet still flows in the page" do
    run = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :running)

    get tool_run_path(run)

    assert_response :success
    assert_select ".chat-screen", count: 0
    assert_select "h1", text: "Check in"
  end

  test "a draft run is untouched by the chat shell" do
    run = users(:one).tool_runs.create!(tool_slug: "dispute_letter", status: :done,
      inputs: { document_id: @document.id, intent: "remove the charge" })

    get tool_run_path(run)

    assert_response :success
    assert_select ".chat-screen", count: 0
    assert_select "h1", text: "Draft a dispute letter"
  end

  test "the composer asks the on-screen keyboard for the right shape" do
    run = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Hi")

    get tool_run_path(run)

    assert_select "#chat-composer[enterkeyhint=send][autocapitalize=sentences][autocorrect=on]"
  end

  test "a turn keeps the id the client drew it with, so the morph matches them" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { topic: "x" }, status: :done)

    post tool_run_messages_path(run), params: { content: "Drawn already", client_token: "cabc123" }

    assert_equal "cabc123", run.tool_run_messages.sole.client_token
    get tool_run_path(run)
    assert_select "#chat-msg-cabc123"
  end

  test "a turn sent without a token falls back to its own id" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { topic: "x" }, status: :done)

    post tool_run_messages_path(run), params: { content: "Plain form post" }
    message = run.tool_run_messages.sole

    assert_nil message.client_token
    get tool_run_path(run)
    assert_select "#chat-msg-#{message.id}"
  end

  test "new 404s for an unknown tool" do
    get new_tool_run_path("nonsense")
    assert_response :not_found
  end

  test "deleting a chat run destroys the transcript but not the recap note (D33)" do
    run = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Hi there")
    recap = users(:one).notes.create!(title: "Check-in recap", body: "Kept.")
    run.tool_run_items.create!(item: recap)

    delete tool_run_path(run)
    assert_redirected_to section_path("health")
    assert_not ToolRun.exists?(run.id)
    assert_empty ToolRunMessage.where(tool_run_id: run.id)
    assert Note.exists?(recap.id)
  end

  test "you can't delete another user's run" do
    run = users(:two).tool_runs.create!(tool_slug: "check_in", inputs: {})

    delete tool_run_path(run)
    assert_response :not_found
    assert ToolRun.exists?(run.id)
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

  test "new prefills inputs from the query string — the D28 routing entry point" do
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

  test "new renders the person picker from visible people" do
    users(:one).people.create!(name: "Rosa")
    users(:two).people.create!(name: "Private Pete")

    get new_tool_run_path("reconnect")

    assert_response :success
    assert_select "select#inputs_person_id option", text: "Rosa"
    assert_select "select#inputs_person_id option", text: "Private Pete", count: 0
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

  test "recap marks itself in flight and a second click can't file a duplicate" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Hi!")

    assert_enqueued_with(job: ChatRecapJob) { post recap_tool_run_path(run) }
    assert run.reload.recap_pending?

    assert_no_enqueued_jobs(only: ChatRecapJob) { post recap_tool_run_path(run) }

    get tool_run_path(run)
    assert_match "Saving recap…", response.body
  end

  test "the composer disables send and shows the typing indicator while awaiting a reply" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Where shall we start?")
    run.tool_run_messages.create!(role: :user, content: "Fractions, please")

    get tool_run_path(run)

    assert_response :success
    assert_select "button[type=submit][disabled][data-locked]"
    assert_select "#chat-transcript span.animate-bounce", count: 3
  end

  test "the composer ships enabled and unlocked when it's the user's turn" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Where shall we start?")

    get tool_run_path(run)

    assert_response :success
    assert_select "button[type=submit][data-locked]", count: 0, message: "no lock when nothing is in flight"
    assert_select "button[type=submit][disabled]", count: 0, message: "sends without JS"
  end

  test "the page declares morphing refreshes, so sending a message doesn't reset the scroll" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)

    get tool_run_path(run)

    # Both composers redirect back to the page they're on, and every chat job
    # broadcasts a refresh — without these the reader is thrown to the top of
    # the page twice per turn.
    assert_select "meta[name=turbo-refresh-method][content=morph]"
    assert_select "meta[name=turbo-refresh-scroll][content=preserve]"
    assert_select "#chat-transcript", count: 1, message: "the scroller is id'd so a morph matches it"
  end

  test "a quick reply the user already sent is not offered again" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Where shall we start?")
    run.tool_run_messages.create!(role: :user, content: "Quiz me")
    run.tool_run_messages.create!(role: :assistant, content: "What is 1/2 + 1/4?")

    get tool_run_path(run)

    assert_response :success
    assert_select "[data-chat-input-text-param=?]", "Quiz me", count: 0
    assert_select "[data-chat-input-text-param]", minimum: 1, message: "the untaken suggestions stay"
  end

  test "an assistant turn's light markdown renders as markup, and a user's does not" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Two **halves**:\n- one\n- two")
    run.tool_run_messages.create!(role: :user, content: "so 2 * 2 and **not bold**")

    get tool_run_path(run)

    assert_select ".bubble-assistant strong", text: "halves"
    assert_select ".bubble-assistant li", count: 2
    assert_select ".bubble-user strong", count: 0
    assert_match "**not bold**", response.body
  end

  test "a failed turn offers try again, which drops the notice and re-enqueues the reply" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Hi!")
    run.tool_run_messages.create!(role: :user, content: "What is 1/2 + 1/4?")
    run.tool_run_messages.create!(role: :notice, content: "The model returned an empty reply — try again.")

    get tool_run_path(run)
    assert_select "form[action=?]", retry_reply_tool_run_path(run)

    assert_enqueued_with(job: ChatTurnJob) { post retry_reply_tool_run_path(run) }
    assert run.reload.awaiting_reply?, "the thinking indicator comes back"
    assert_not run.tool_run_messages.notice_role.exists?
  end

  test "try again does nothing when the last turn didn't fail" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "All answered.")

    assert_no_enqueued_jobs { post retry_reply_tool_run_path(run) }
    assert_redirected_to tool_run_path(run)
  end

  test "a chat page offers the tool's quick replies and links the previous session's recap" do
    earlier = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    recap = users(:one).notes.create!(title: "Tutoring recap — fractions", body: "We covered halves.")
    earlier.tool_run_items.create!(item: recap)

    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "fractions" }, status: :done)
    run.tool_run_messages.create!(role: :assistant, content: "Welcome back!")

    get tool_run_path(run)

    assert_response :success
    assert_match "Quiz me", response.body
    assert_match "Picking up from last time", response.body
    assert_select "a[href=?]", note_path(recap), text: "Tutoring recap — fractions"
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
    assert_match "nothing ever goes out without your explicit click", response.body
  end
end
