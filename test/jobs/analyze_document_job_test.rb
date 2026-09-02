require "test_helper"

class AnalyzeDocumentJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @document = users(:one).documents.create!(title: "Lease agreement")
    @document.file.attach(io: StringIO.new("Monthly rent is $1,200, due on the 1st."),
      filename: "lease.txt", content_type: "text/plain")
  end

  test "analyzes a text document: summary, suggestions, extracted text" do
    stub_llm(summary: "Your lease sets rent at $1,200, due on the 1st of each month.",
             sections: [ "renting", "money", "not-a-real-slug" ])

    AnalyzeDocumentJob.perform_now(@document)

    @document.reload
    assert @document.analysis_analyzed?
    assert_match "$1,200", @document.summary
    assert_equal [ "renting", "money" ], @document.suggested_sections
    assert_match "Monthly rent", @document.extracted_text
    assert_nil @document.analysis_error
    # Untagged documents get filed automatically (D16).
    assert_equal [ sections(:money), sections(:renting) ].to_set, @document.sections.to_set
  end

  test "hand-tagged documents keep their tags; suggestions stay suggestions" do
    @document.sections << sections(:health)
    stub_llm(summary: "A lease.", sections: [ "renting" ])

    AnalyzeDocumentJob.perform_now(@document)

    @document.reload
    assert_equal [ sections(:health) ], @document.sections.to_a
    assert_equal [ sections(:renting) ], @document.suggested_section_records
  end

  test "sends the document text and taxonomy to the model" do
    stub_llm(summary: "ok", sections: [])
    AnalyzeDocumentJob.perform_now(@document)

    assert_requested(:post, ENDPOINT) do |request|
      body = JSON.parse(request.body)
      content = body["messages"].last["content"]
      content.include?("Monthly rent is $1,200") && content.include?("renting — Rights · Renting")
    end
  end

  test "a pay stub's facts are extracted, whitelisted, and stored" do
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        summary: "A pay stub from Acme.", sections: [ "career" ],
        pay_stub: {
          employer: "Acme Logistics", pay_date: "2026-03-15", rate: "$19.00",
          hours: "80", gross: "$1,520.00", net: "$1,201.33",
          deductions: [ { label: "Federal income tax", amount: "$142.00" }, "garbage" ],
          surprise_key: "dropped"
        }
      }.to_json } } ] }.to_json
    )

    AnalyzeDocumentJob.perform_now(@document)

    facts = @document.reload.extracted_facts["pay_stub"]
    assert_equal "Acme Logistics", facts["employer"]
    assert_equal "$19.00", facts["rate"]
    assert_equal [ { "label" => "Federal income tax", "amount" => "$142.00" } ], facts["deductions"]
    assert_nil facts["surprise_key"]
    # A first stub has nothing to compare against — no comp event.
    assert_empty Career::CompChange.scope(users(:one))
  end

  test "a rate change against the previous stub lands on the comp timeline" do
    users(:one).documents.create!(title: "March stub",
      extracted_facts: { "pay_stub" => { "rate" => "19", "pay_date" => "2026-03-15" } })
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        summary: "A pay stub.", sections: [ "career" ],
        pay_stub: { rate: "21", pay_date: "2026-04-15" }
      }.to_json } } ] }.to_json
    )

    AnalyzeDocumentJob.perform_now(@document)

    event = Career::CompChange.scope(users(:one)).sole
    assert_equal "Comp change: $19.00 → $21.00/hr", event.title
    assert_equal [ sections(:career) ], event.sections.to_a
  end

  # ── Landings (D-document-intake) ───────────────────────────────────────

  test "what the document proposes is validated and stored, and nothing lands" do
    @document.sections << sections(:health)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        summary: "A discharge sheet.", sections: [ "health" ],
        landings: [
          { kind: "event", title: "Rex — vaccinations", on: "2026-08-12", extra: "dropped" },
          { kind: "person", name: "Dr. Alvarez", relationship: "Vet" },
          { kind: "nonsense", title: "x" }
        ]
      }.to_json } } ] }.to_json
    )

    assert_no_difference [ -> { Event.count }, -> { Person.count } ] do
      AnalyzeDocumentJob.perform_now(@document)
    end

    landings = @document.reload.landings
    assert_equal %w[ event person ], landings.map { |entry| entry["kind"] }
    assert_equal %w[ proposed proposed ], landings.map { |entry| entry["status"] }
    assert_equal({ "title" => "Rex — vaccinations", "on" => "2026-08-12" }, landings.first["attributes"])
    assert @document.landings_to_review?
    # The prompt carried the registry and the document's filing.
    assert_requested(:post, ENDPOINT) do |request|
      body = JSON.parse(request.body)
      body["messages"].first["content"].include?("- event — ") &&
        body["messages"].last["content"].include?("Filed under: Health")
    end
  end

  test "re-analysis keeps what the user already ruled on and never re-proposes it" do
    @document.update!(landings: [
      { "kind" => "event", "fingerprint" => "event:rex-vaccinations:2026-08-12", "status" => "saved",
        "attributes" => { "title" => "Rex — vaccinations", "on" => "2026-08-12" } },
      { "kind" => "task", "fingerprint" => "task:call-the-vet", "status" => "skipped", "attributes" => { "title" => "Call the vet" } },
      { "kind" => "note", "fingerprint" => "note:old-proposal", "status" => "proposed", "attributes" => { "title" => "Old proposal" } }
    ])
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        summary: "Again.", sections: [],
        landings: [
          { kind: "event", title: "Rex — vaccinations", on: "2026-08-12" },
          { kind: "task", title: "Call the vet" },
          { kind: "note", title: "New fact" }
        ]
      }.to_json } } ] }.to_json
    )

    AnalyzeDocumentJob.perform_now(@document)

    landings = @document.reload.landings
    assert_equal [ %w[ event saved ], %w[ task skipped ], %w[ note proposed ] ],
      landings.map { |entry| [ entry["kind"], entry["status"] ] }
    assert_equal "New fact", landings.last.dig("attributes", "title"), "the stale proposal was replaced"
  end

  test "the reader's title replaces a file-name title and never a typed one" do
    stub_llm(summary: "ok", sections: [], title: "Rex — vet discharge sheet")

    named = users(:one).documents.new(title: "")
    named.file.attach(io: StringIO.new("x"), filename: "IMG_4032.txt", content_type: "text/plain")
    named.save!
    assert_equal "IMG 4032", named.title
    AnalyzeDocumentJob.perform_now(named)
    assert_equal "Rex — vet discharge sheet", named.reload.title

    AnalyzeDocumentJob.perform_now(@document)
    assert_equal "Lease agreement", @document.reload.title
  end

  test "documents with no pay-stub facts store an empty facts hash" do
    stub_llm(summary: "A lease.", sections: [ "renting" ])

    AnalyzeDocumentJob.perform_now(@document)

    assert_equal({}, @document.reload.extracted_facts)
  end

  test "permanent provider errors mark the document failed with a friendly message" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)

    AnalyzeDocumentJob.perform_now(@document)

    @document.reload
    assert @document.analysis_failed?
    assert_match "Incorrect API key", @document.analysis_error
    assert_requested :post, ENDPOINT, times: 1
  end

  test "a transient error keeps the document processing while a retry is pending" do
    stub_request(:post, ENDPOINT).to_return(status: 429, body: { error: { message: "Rate limit reached" } }.to_json)

    AnalyzeDocumentJob.perform_now(@document)

    @document.reload
    assert @document.analysis_processing?, "a pending retry must not flash a failure at the user"
    assert_nil @document.analysis_error
    assert_enqueued_jobs 1, only: AnalyzeDocumentJob
  end

  test "a transient error that clears analyses the document on the retry" do
    stub_request(:post, ENDPOINT)
      .to_return(status: 503, body: "gateway down").then
      .to_return(status: 200, body: { choices: [ { message: { content: {
        summary: "A lease.", sections: [ "renting" ]
      }.to_json } } ] }.to_json)

    perform_enqueued_jobs { AnalyzeDocumentJob.perform_later(@document) }

    @document.reload
    assert @document.analysis_analyzed?
    assert_nil @document.analysis_error
  end

  test "a transient error that never clears marks the document failed once out of chances" do
    stub_request(:post, ENDPOINT).to_return(status: 429, body: { error: { message: "Rate limit reached" } }.to_json)

    perform_enqueued_jobs { AnalyzeDocumentJob.perform_later(@document) }

    @document.reload
    assert @document.analysis_failed?
    assert_match "Rate limit", @document.analysis_error
    assert_requested :post, ENDPOINT, times: RetriesModelCalls::ATTEMPTS
  end

  test "unsupported file types fail without calling the provider" do
    @document.file.attach(io: StringIO.new("pretend-bytes"), filename: "archive.zip", content_type: "application/zip")

    AnalyzeDocumentJob.perform_now(@document)

    assert @document.reload.analysis_failed?
    assert_match "application/zip", @document.analysis_error
    assert_not_requested :post, ENDPOINT
  end

  # ── Reading images and scans (INTAKE_PLAN W1) ──────────────────────────

  test "a PDF with a text layer is read as text, no vision needed" do
    attach_pdf(@document, text: "Rent is due on the first")
    stub_llm(summary: "A lease.", sections: [ "renting" ])

    AnalyzeDocumentJob.perform_now(@document)

    assert @document.reload.analysis_analyzed?
    assert_match "Rent is due", @document.extracted_text
    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.is_a?(String) && content.include?("Rent is due on the first")
    end
  end

  test "an image without a vision model fails honestly, without calling the provider" do
    attach_image(@document)

    AnalyzeDocumentJob.perform_now(@document)

    assert @document.reload.analysis_failed?
    assert_match "can't read images", @document.analysis_error
    assert_match "vision in Settings", @document.analysis_error
    assert_not_requested :post, ENDPOINT
  end

  test "an image goes to a vision model as a page image, and the transcription becomes the document's text" do
    model_profiles(:smith).update!(vision: true)
    attach_image(@document)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        summary: "A vet's discharge sheet for Rex.", sections: [ "health" ],
        text: "ANIMAL HOSPITAL\nPatient: Rex\nRabies booster given 12 Aug 2026"
      }.to_json } } ] }.to_json
    )

    AnalyzeDocumentJob.perform_now(@document)

    @document.reload
    assert @document.analysis_analyzed?
    assert_match "Rabies booster", @document.extracted_text
    assert_requested(:post, ENDPOINT) do |request|
      body = JSON.parse(request.body)
      content = body["messages"].last["content"]
      image = content.is_a?(Array) && content.find { |part| part["type"] == "image_url" }
      image && image.dig("image_url", "url").start_with?("data:image/webp;base64,") &&
        body["messages"].first["content"].include?("transcription")
    end
  end

  test "a scanned PDF with no text layer is rendered to page images for a vision model" do
    model_profiles(:smith).update!(vision: true)
    attach_pdf(@document)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: { summary: "A scan.", sections: [], text: "[unreadable]" }.to_json } } ] }.to_json
    )

    AnalyzeDocumentJob.perform_now(@document)

    assert @document.reload.analysis_analyzed?
    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.is_a?(Array) && content.count { |part| part["type"] == "image_url" } == 1
    end
  end

  test "a scanned PDF without a vision model says which rung is missing" do
    attach_pdf(@document)

    AnalyzeDocumentJob.perform_now(@document)

    assert @document.reload.analysis_failed?
    assert_match "scan with no text", @document.analysis_error
    assert_not_requested :post, ENDPOINT
  end

  test "does nothing without a configured model profile" do
    document = users(:outsider).documents.create!(title: "No AI here")

    AnalyzeDocumentJob.perform_now(document)

    assert_nil document.reload.analysis_status
    assert_not_requested :post, ENDPOINT
  end

  private
    def stub_llm(summary:, sections:, title: nil)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { summary: summary, sections: sections, title: title }.compact.to_json } } ] }.to_json
      )
    end
end
