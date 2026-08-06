require "test_helper"

class CategorizeNoteJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @note = users(:one).notes.create!(body: "Allergic to penicillin — mention at every new appointment.")
  end

  test "files the note into sections and titles it" do
    stub_llm(sections: [ "health", "not-a-real-slug" ], title: "Penicillin allergy")

    CategorizeNoteJob.perform_now(@note)

    @note.reload
    assert_equal [ sections(:health) ], @note.sections.to_a
    assert_equal "Penicillin allergy", @note.title
  end

  test "never overwrites a title the user gave" do
    @note.update!(title: "Med notes")
    stub_llm(sections: [ "health" ], title: "Penicillin allergy")

    CategorizeNoteJob.perform_now(@note)

    assert_equal "Med notes", @note.reload.title
  end

  test "sends the note body and taxonomy to the model" do
    stub_llm(sections: [], title: "")
    CategorizeNoteJob.perform_now(@note)

    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.include?("Allergic to penicillin") && content.include?("renting — Rights · Renting")
    end
  end

  test "skips notes the user already tagged, without calling the provider" do
    @note.sections << sections(:health)

    CategorizeNoteJob.perform_now(@note)

    assert_not_requested :post, ENDPOINT
  end

  test "does nothing without a configured model profile" do
    note = users(:outsider).notes.create!(body: "No AI here")

    CategorizeNoteJob.perform_now(note)

    assert_not_requested :post, ENDPOINT
  end

  test "provider errors leave the note unfiled instead of raising" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    CategorizeNoteJob.perform_now(@note)

    @note.reload
    assert_empty @note.sections
    assert_nil @note.title
  end

  private
    def stub_llm(sections:, title:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { sections: sections, title: title }.to_json } } ] }.to_json
      )
    end
end
