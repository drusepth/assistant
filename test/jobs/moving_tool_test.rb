require "test_helper"

# The first Situation (M2.4) and the Q7 pressure test: a Situation is a
# plan tool whose brief spans sections, and every cross-section behavior —
# per-step multi-tagging, scheduled steps, goal filing — rides the shared
# breakdown pipeline unchanged.
class MovingToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "moving",
      inputs: { "details" => "across town to a 2-bed, end of June", "wrinkles" => "kids changing schools" }
    )
  end

  test "one run plans the whole move, with steps multi-tagged across sections" do
    stub_llm(
      sections: %w[ renting money ],
      target_on: "2027-06-30",
      steps: [
        { title: "Give written notice to the landlord", due_on: Date.current.iso8601, sections: %w[ renting ] },
        { title: "Send the forwarding address for the deposit", due_on: nil, sections: %w[ renting money ] },
        { title: "Start the school transfer paperwork", due_on: nil, sections: %w[ people education ] },
        { title: "Schedule electricity stop/start", due_on: nil, sections: %w[ bills ] }
      ]
    )

    ToolRunJob.perform_now(@run)

    @run.reload
    assert @run.done?

    goal = @run.items.grep(Goal).sole
    assert_equal "Moving — across town to a 2-bed, end of June", goal.title
    assert_equal "kids changing schools", goal.description
    assert_equal Date.new(2027, 6, 30), goal.target_on
    assert_not_nil goal.broken_down_at
    [ :renting, :money, :people ].each do |slug|
      assert_includes goal.sections, sections(slug), "the goal is findable everywhere the situation lives"
    end

    steps = @run.items.grep(Task).sort_by(&:id)
    assert_equal 4, steps.count
    assert_equal [ goal ] * 4, steps.map(&:goal)

    deposit = steps.second
    assert_equal [ sections(:renting), sections(:money) ].sort_by(&:id), deposit.sections.sort_by(&:id),
      "one step, two lenses — the Q7 cross-section test"
    school = steps.third
    assert_includes school.sections, sections(:education),
      "steps reach sections the tool isn't even registered on"
    assert steps.first.today?, "notice is due now, so it surfaces on Today"
  end

  test "the model call carries the situation brief and the user's specifics" do
    stub_llm(sections: [], target_on: nil, steps: [])

    ToolRunJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("security deposit can follow") &&
        request.body.include?("Tag every step with the sections it truly touches") &&
        request.body.include?("kids changing schools")
    end
  end

  test "a provider error fails the run but leaves an ordinary retryable goal" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    ToolRunJob.perform_now(@run)

    assert @run.reload.failed?
    goal = @run.items.grep(Goal).sole
    assert_empty goal.tasks
    assert_not_nil goal.broken_down_at, "a failed run must not leave the goal spinning"
  end

  private
    def stub_llm(sections:, target_on:, steps:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          sections: sections, target_on: target_on, steps: steps
        }.to_json } } ] }.to_json
      )
    end
end
