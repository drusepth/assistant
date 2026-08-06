require "test_helper"

class CategorizeGoalJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @goal = users(:one).goals.create!(title: "Save $5k by December")
  end

  test "files the goal into sections and picks up the target date" do
    stub_llm(sections: [ "money", "not-a-real-slug" ], target_on: "2026-12-01")

    CategorizeGoalJob.perform_now(@goal)

    @goal.reload
    assert_equal [ sections(:money) ], @goal.sections.to_a
    assert_equal Date.new(2026, 12, 1), @goal.target_on
  end

  test "never overwrites a target date the user already set" do
    @goal.update!(target_on: Date.new(2026, 10, 1))
    stub_llm(sections: [ "money" ], target_on: "2026-12-01")

    CategorizeGoalJob.perform_now(@goal)

    assert_equal Date.new(2026, 10, 1), @goal.reload.target_on
  end

  test "skips goals the user already tagged, without calling the provider" do
    @goal.sections << sections(:money)

    CategorizeGoalJob.perform_now(@goal)

    assert_not_requested :post, ENDPOINT
  end

  test "provider errors leave the goal unsorted instead of raising" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    CategorizeGoalJob.perform_now(@goal)

    assert_empty @goal.reload.sections
  end

  private
    def stub_llm(sections:, target_on:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { sections: sections, target_on: target_on }.to_json } } ] }.to_json
      )
    end
end
