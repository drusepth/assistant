require "test_helper"

# The retrieval gate (D-mastery-evidence): finishing a quiz is the explicit
# click that records the verdict — mastery moves on evidence, misses become
# review cards, and the session leaves a durable study_log line.
class QuizMeToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @topic = topics(:fractions_compare)
    @run = users(:one).tool_runs.create!(tool_slug: "quiz_me", inputs: { "topic_id" => @topic.id.to_s })
  end

  test "the opening question knows the topic and its place in the tree" do
    stub_chat("Two questions on comparing fractions. First: which is bigger, 2/3 or 3/5?")

    ToolRunJob.perform_now(@run)

    assert @run.reload.done?
    assert_requested(:post, ENDPOINT) do |request|
      # the prompt carries the topic and the mastered neighbors to build on
      request.body.include?("Comparing unlike denominators") &&
        request.body.include?("Percentages in the wild")
    end
  end

  test "finishing grades the quiz: mastery advances on evidence, misses become cards, the log gets a line" do
    @run.tool_run_messages.create!(role: :assistant, content: "Which is bigger, 2/3 or 3/5?")
    @run.tool_run_messages.create!(role: :user, content: "2/3 — common denominator 15ths makes it 10 vs 9.")
    stub_recap(
      recap: { title: "Quiz — comparing fractions", body: "Clean sweep, one slip on mixed numbers." },
      verdict: { state: "mastered", reason: "answered everything, applied included" },
      missed: [ { prompt: "Which is bigger: 1 1/3 or 4/3?", answer: "They're equal." } ]
    )

    ChatRecapJob.perform_now(@run)

    @topic.reload
    assert @topic.mastered?
    assert_equal "quiz", @topic.mastery_evidence
    assert_equal Date.current, @topic.mastered_on

    card = @topic.review_items.sole
    assert_equal "Which is bigger: 1 1/3 or 4/3?", card.prompt
    assert_equal users(:one), card.user

    log = users(:one).study_logs.sole
    assert_equal subjects(:algebra), log.subject
    assert_equal "review", log.activity

    note = @run.reload.items.grep(Note).sole
    assert_match(/Clean sweep/, note.body)
  end

  test "one bad afternoon never demotes a mastered topic — sliding back is FSRS's call" do
    mastered = topics(:percentages)
    run = users(:one).tool_runs.create!(tool_slug: "quiz_me", inputs: { "topic_id" => mastered.id.to_s })
    run.tool_run_messages.create!(role: :user, content: "no idea")
    stub_recap(
      recap: { title: "Quiz — percentages", body: "Rough day." },
      verdict: { state: "learning", reason: "missed everything" },
      missed: []
    )

    ChatRecapJob.perform_now(run)

    assert mastered.reload.mastered?
  end

  test "a rusty topic re-earns green through the same evidence" do
    rusty = topics(:friction)
    rusty.decay!
    run = users(:one).tool_runs.create!(tool_slug: "quiz_me", inputs: { "topic_id" => rusty.id.to_s })
    run.tool_run_messages.create!(role: :user, content: "answers")
    stub_recap(
      recap: { title: "Quiz — friction", body: "Shored up." },
      verdict: { state: "mastered", reason: "solid" },
      missed: []
    )

    ChatRecapJob.perform_now(run)

    assert rusty.reload.mastered?
  end

  test "another member's topic is unreachable" do
    run = users(:one).tool_runs.create!(tool_slug: "quiz_me", inputs: { "topic_id" => topics(:bob_veto).id.to_s })
    stub_chat("hello")

    ToolRunJob.perform_now(run)

    assert run.reload.failed?
    assert topics(:bob_veto).reload.learning?
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
