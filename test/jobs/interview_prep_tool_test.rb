require "test_helper"

class InterviewPrepToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "lands the prep sheet with the research checklist and routes to the mock interview" do
    win = Career::WinLog.log!(user: users(:one), text: "Caught the inventory error before the audit")
    assert win.persisted?
    run = users(:one).tool_runs.create!(
      tool_slug: "interview_prep",
      inputs: { "role" => "Warehouse shift lead at Acme", "listing" => "Leads a team of 12. Requires inventory experience.",
                "concerns" => "the gap in my resume" }
    )
    stub_llm(
      prep: { title: "Prep — shift lead at Acme", body: "Their asks, your answers: inventory experience — your logged win about the audit." },
      research: [ "Acme's warehouse locations", "typical shift structure" ],
      follow_ups: [ { title: "Reread the prep sheet the night before", due_on: nil } ]
    )

    run_and_add_all(run)

    run.reload
    assert run.done?

    note = run.items.grep(Note).sole
    assert_equal "Prep — shift lead at Acme", note.title
    assert_includes note.body, "Before the interview, look up:\n- Acme's warehouse locations"
    assert_equal [ sections(:career) ], note.sections.to_a

    assert_equal [ { "slug" => "mock_interview",
                    "inputs" => { "focus" => "Warehouse shift lead at Acme" },
                    "reason" => "Rehearse it out loud — the prep sheet is the study guide, the mock is the practice test." } ],
      run.output["next_tools"]

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Leads a team of 12") &&
        request.body.include?("gap in my resume") &&
        request.body.include?("Caught the inventory error")
    end
  end

  test "a vault document works in place of pasted text and joins the filing" do
    listing = users(:one).documents.create!(title: "Acme posting", extracted_text: "Shift lead role, nights.")
    listing.sections << sections(:career)
    run = users(:one).tool_runs.create!(
      tool_slug: "interview_prep",
      inputs: { "role" => "Shift lead", "document_id" => listing.id.to_s }
    )
    stub_llm(prep: { title: "t", body: "b" }, research: [], follow_ups: [])

    run_and_add_all(run)

    assert run.reload.done?
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("Shift lead role, nights.") }
  end

  test "a listing URL is fetched by the app and joins the prompt" do
    Web::Fetch.resolver = Class.new { def getaddresses(_h) = [ "93.184.216.34" ] }.new
    stub_request(:get, "https://jobs.example.com/shift-lead").to_return(
      status: 200, headers: { "Content-Type" => "text/html" },
      body: "<html><body>Night shift lead. Forklift certification required.</body></html>"
    )
    run = users(:one).tool_runs.create!(
      tool_slug: "interview_prep",
      inputs: { "role" => "Shift lead", "listing_url" => "https://jobs.example.com/shift-lead" }
    )
    stub_llm(prep: { title: "t", body: "b" }, research: [], follow_ups: [])

    run_and_add_all(run)

    assert run.reload.done?
    assert_requested(:post, ENDPOINT) { |request| request.body.include?("Forklift certification") }
  ensure
    Web::Fetch.resolver = Resolv
  end

  test "an unreachable listing URL fails the run with the paste fallback named" do
    Web::Fetch.resolver = Class.new { def getaddresses(_h) = [ "93.184.216.34" ] }.new
    stub_request(:get, "https://jobs.example.com/gone").to_return(status: 404, body: "")
    run = users(:one).tool_runs.create!(
      tool_slug: "interview_prep",
      inputs: { "role" => "Shift lead", "listing_url" => "https://jobs.example.com/gone" }
    )

    run_and_add_all(run)

    assert run.reload.failed?
    assert_match(/Pasting the text works too/, run.error)
    assert_not_requested :post, ENDPOINT
  ensure
    Web::Fetch.resolver = Resolv
  end

  test "no listing at all fails with a friendly message before any model call" do
    run = users(:one).tool_runs.create!(tool_slug: "interview_prep", inputs: { "role" => "Shift lead" })

    run_and_add_all(run)

    assert run.reload.failed?
    assert_match(/Paste the listing/, run.error)
    assert_not_requested :post, ENDPOINT
  end

  private
    def stub_llm(prep:, research:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          prep: prep, research: research, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
