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

  test "provider errors mark the document failed with a friendly message" do
    stub_request(:post, ENDPOINT).to_return(status: 429, body: { error: { message: "Rate limit reached" } }.to_json)

    AnalyzeDocumentJob.perform_now(@document)

    @document.reload
    assert @document.analysis_failed?
    assert_match "Rate limit", @document.analysis_error
  end

  test "unsupported file types fail without calling the provider" do
    @document.file.attach(io: StringIO.new("pretend-bytes"), filename: "scan.png", content_type: "image/png")

    AnalyzeDocumentJob.perform_now(@document)

    assert @document.reload.analysis_failed?
    assert_match "image/png", @document.analysis_error
    assert_not_requested :post, ENDPOINT
  end

  test "does nothing without a configured model profile" do
    document = users(:outsider).documents.create!(title: "No AI here")

    AnalyzeDocumentJob.perform_now(document)

    assert_nil document.reload.analysis_status
    assert_not_requested :post, ENDPOINT
  end

  private
    def stub_llm(summary:, sections:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { summary: summary, sections: sections }.to_json } } ] }.to_json
      )
    end
end
