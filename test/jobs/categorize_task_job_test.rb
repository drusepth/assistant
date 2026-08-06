require "test_helper"

class CategorizeTaskJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @task = users(:one).tasks.create!(title: "Renew passport by Friday")
  end

  test "files the task into sections and picks up the due date" do
    stub_llm(sections: [ "rights", "not-a-real-slug" ], due_on: "2026-08-07")

    CategorizeTaskJob.perform_now(@task)

    @task.reload
    assert_equal [ sections(:rights) ], @task.sections.to_a
    assert_equal Date.new(2026, 8, 7), @task.due_on
  end

  test "sends the task, today's date, and taxonomy to the model" do
    stub_llm(sections: [], due_on: nil)
    CategorizeTaskJob.perform_now(@task)

    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.include?("Renew passport by Friday") &&
        content.include?(Date.current.iso8601) &&
        content.include?("renting — Rights · Renting")
    end
  end

  test "never overwrites a due date the user already set" do
    @task.update!(due_on: Date.new(2026, 9, 1))
    stub_llm(sections: [ "money" ], due_on: "2026-08-07")

    CategorizeTaskJob.perform_now(@task)

    @task.reload
    assert_equal Date.new(2026, 9, 1), @task.due_on
    assert_equal [ sections(:money) ], @task.sections.to_a
  end

  test "skips tasks the user already tagged, without calling the provider" do
    @task.sections << sections(:health)

    CategorizeTaskJob.perform_now(@task)

    assert_equal [ sections(:health) ], @task.reload.sections.to_a
    assert_not_requested :post, ENDPOINT
  end

  test "does nothing without a configured model profile" do
    task = users(:outsider).tasks.create!(title: "No AI here")

    CategorizeTaskJob.perform_now(task)

    assert_not_requested :post, ENDPOINT
  end

  test "provider errors leave the task unsorted instead of raising" do
    stub_request(:post, ENDPOINT).to_return(status: 429, body: { error: { message: "Rate limit reached" } }.to_json)

    CategorizeTaskJob.perform_now(@task)

    assert_empty @task.reload.sections
  end

  test "an invalid due date from the model is ignored" do
    stub_llm(sections: [], due_on: "next Friday-ish")

    CategorizeTaskJob.perform_now(@task)

    assert_nil @task.reload.due_on
  end

  private
    def stub_llm(sections:, due_on:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { sections: sections, due_on: due_on }.to_json } } ] }.to_json
      )
    end
end
