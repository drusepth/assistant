require "test_helper"

# Find my edge (docs/EDUCATION_PLAN.md §6): placement stamps starting
# mastery generously, forward-only, and only inside the learner's own tree.
class PlacementToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @subject = subjects(:algebra)
    @run = users(:one).tool_runs.create!(tool_slug: "placement", inputs: { "subject_id" => @subject.id.to_s })
  end

  test "the prompt carries the syllabus with ids as the contract" do
    stub_chat("Let's find your edge. What's 3/4 as a percentage?")

    ToolRunJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("[#{topics(:fractions_arithmetic).id}]") &&
        request.body.include?("Fraction arithmetic")
    end
  end

  test "finishing stamps placement marks — forward only, own tree only" do
    @run.tool_run_messages.create!(role: :user, content: "75%")
    stub_recap(
      recap: { title: "Placement — everyday math", body: "Your edge is fraction arithmetic." },
      placements: [
        { topic_id: topics(:fractions_arithmetic).id, state: "mastered" },
        { topic_id: topics(:fractions_compare).id, state: "learning" },
        { topic_id: topics(:bob_veto).id, state: "mastered" }
      ]
    )

    ChatRecapJob.perform_now(@run)

    assert topics(:fractions_arithmetic).reload.mastered?
    assert_equal "placement", topics(:fractions_arithmetic).mastery_evidence
    assert topics(:fractions_compare).reload.practicing?, "placement never demotes what evidence already set"
    assert topics(:bob_veto).reload.learning?, "another learner's tree is out of reach"

    assert_equal "lesson", users(:one).study_logs.sole.activity
  end

  private
    def stub_chat(content)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: content } } ] }.to_json
      )
    end

    def stub_recap(payload)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: payload.to_json } } ] }.to_json
      )
    end
end
