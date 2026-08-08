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

  test "stores the model's guiding questions for the task-page conversation" do
    stub_llm(sections: [], due_on: nil,
      questions: [ " What would success look like? ", "", 123, "Who could you ask?" ])

    CategorizeTaskJob.perform_now(@task)

    assert_equal [ "What would success look like?", "Who could you ask?" ],
      @task.reload.guiding_questions
  end

  test "an errand's empty questions leave the stock opener in place" do
    stub_llm(sections: [], due_on: nil, questions: [])

    CategorizeTaskJob.perform_now(@task)

    assert_equal [], @task.reload.guiding_questions
    assert_equal [ Task::FALLBACK_OPENER ], @task.conversation_openers
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

  test "a permanent provider error leaves the task unsorted instead of raising" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)

    CategorizeTaskJob.perform_now(@task)

    assert_empty @task.reload.sections
    assert_requested :post, ENDPOINT, times: 1
    assert_no_enqueued_jobs
  end

  test "a swallowed provider error is still recorded for /admin" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)

    assert_difference -> { AppError.count }, 1 do
      CategorizeTaskJob.perform_now(@task)
    end

    recorded = AppError.recent.first
    assert_equal "CategorizeTaskJob", recorded.source
    assert_equal "Llm::Error", recorded.error_class
    assert_equal users(:one), recorded.user
    assert_equal @task.id, recorded.context["task_id"]
  end

  test "a transient provider error is retried rather than swallowed" do
    stub_request(:post, ENDPOINT).to_return(status: 429, body: { error: { message: "Rate limit reached" } }.to_json)

    assert_no_difference -> { AppError.count } do
      CategorizeTaskJob.perform_now(@task)
    end

    assert_enqueued_jobs 1, only: CategorizeTaskJob
  end

  test "a rate limit that clears sorts the task on the retry" do
    stub_request(:post, ENDPOINT)
      .to_return(status: 429, body: { error: { message: "Rate limit reached" } }.to_json).then
      .to_return(status: 200, body: { choices: [ { message: { content: { sections: [ "rights" ], due_on: nil }.to_json } } ] }.to_json)

    perform_enqueued_jobs { CategorizeTaskJob.perform_later(@task) }

    assert_equal [ sections(:rights) ], @task.reload.sections.to_a
    assert_equal 0, AppError.count, "a failure the retry fixed isn't worth logging"
  end

  test "a rate limit that never clears gives up after the attempt budget" do
    stub_request(:post, ENDPOINT).to_return(status: 429, body: { error: { message: "Rate limit reached" } }.to_json)

    perform_enqueued_jobs { CategorizeTaskJob.perform_later(@task) }

    assert_empty @task.reload.sections
    assert_requested :post, ENDPOINT, times: RetriesModelCalls::ATTEMPTS
    assert_equal 1, AppError.count, "one record for the whole run, not one per attempt"
    assert_equal "Llm::TransientError", AppError.recent.first.error_class
  end

  test "an invalid due date from the model is ignored" do
    stub_llm(sections: [], due_on: "next Friday-ish")

    CategorizeTaskJob.perform_now(@task)

    assert_nil @task.reload.due_on
  end

  private
    def stub_llm(sections:, due_on:, questions: [])
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { sections: sections, due_on: due_on, questions: questions }.to_json } } ] }.to_json
      )
    end
end
