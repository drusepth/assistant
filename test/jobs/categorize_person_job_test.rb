require "test_helper"

class CategorizePersonJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @person = users(:one).people.create!(name: "Dr. Alvarez", notes: "My cardiologist at St. Mary's.")
  end

  test "files the person into sections and fills in the relationship" do
    stub_llm(sections: [ "health", "not-a-real-slug" ], relationship: "cardiologist")

    CategorizePersonJob.perform_now(@person)

    @person.reload
    assert_equal [ sections(:health) ], @person.sections.to_a
    assert_equal "cardiologist", @person.relationship
  end

  test "never overwrites a relationship the user gave" do
    @person.update!(relationship: "Heart doctor")
    stub_llm(sections: [ "health" ], relationship: "cardiologist")

    CategorizePersonJob.perform_now(@person)

    assert_equal "Heart doctor", @person.reload.relationship
  end

  test "sends the name and notes to the model" do
    stub_llm(sections: [], relationship: nil)
    CategorizePersonJob.perform_now(@person)

    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.include?("Dr. Alvarez") && content.include?("cardiologist at St. Mary")
    end
  end

  test "skips people the user already tagged, without calling the provider" do
    @person.sections << sections(:health)

    CategorizePersonJob.perform_now(@person)

    assert_not_requested :post, ENDPOINT
  end

  test "provider errors leave the person unfiled instead of raising" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    CategorizePersonJob.perform_now(@person)

    assert_empty @person.reload.sections
  end

  private
    def stub_llm(sections:, relationship:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { sections: sections, relationship: relationship }.to_json } } ] }.to_json
      )
    end
end
