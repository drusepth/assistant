require "test_helper"

class TopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "adds a topic to a strand at the end" do
    post topics_path, params: { topic: { subject_id: subjects(:algebra).id,
      parent_id: topics(:fractions_strand).id, title: "Ratios and rates" } }

    topic = subjects(:algebra).topics.order(:id).last
    assert_equal "Ratios and rates", topic.title
    assert_equal 4, topic.position
  end

  test "manual marking records the learner's own call as self-marked" do
    patch mastery_topic_path(topics(:fractions_arithmetic), state: :mastered)

    topic = topics(:fractions_arithmetic).reload
    assert topic.mastered?
    assert_equal "self_marked", topic.mastery_evidence
    assert_equal Date.current, topic.mastered_on
  end

  test "move swaps with the neighbor inside the same strand" do
    patch move_topic_path(topics(:fractions_arithmetic), direction: :up)

    assert_equal 1, topics(:fractions_arithmetic).reload.position
    assert_equal 2, topics(:fractions_compare).reload.position
  end

  test "planning a topic spawns a linked Education-tagged goal" do
    assert_difference "users(:one).goals.count" do
      post plan_topic_path(topics(:momentum))
    end
    goal = topics(:momentum).reload.goal
    assert_equal "Study Momentum in an ollie", goal.title
    assert_includes goal.sections.map(&:slug), "education"
  end

  test "another member's topics are untouchable" do
    patch mastery_topic_path(topics(:bob_veto), state: :mastered)
    assert_response :not_found
    assert topics(:bob_veto).reload.learning?
  end
end
