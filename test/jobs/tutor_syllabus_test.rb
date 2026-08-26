require "test_helper"

# The curriculum-aware tutor (docs/EDUCATION_PLAN.md §6): entered from a
# syllabus row it knows the topic's place in the learner's tree, and
# wrapping up mines review cards, can move mastery on real evidence, and
# leaves the durable study_log line.
class TutorSyllabusTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @topic = topics(:momentum)
    @run = users(:one).tool_runs.create!(
      tool_slug: "tutor",
      inputs: { "topic" => "Momentum in an ollie", "topic_id" => @topic.id.to_s }
    )
  end

  test "the session knows the topic's place in the tree and the interest frame" do
    stub_chat("Let's talk about what happens when you pop the tail.")

    ToolRunJob.perform_now(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Momentum in an ollie") &&
        request.body.include?("skateboarding") &&
        request.body.include?("Its strand: Forces")
    end
  end

  test "a probed session's recap mines cards, advances the checkpoint, and logs the time" do
    3.times do |i|
      @run.tool_run_messages.create!(role: :assistant, content: "Question #{i}?")
      @run.tool_run_messages.create!(role: :user, content: "Worked answer #{i}")
    end
    stub_recap(
      recap: { title: "Tutoring recap — momentum", body: "Worked p = mv through three tricks." },
      review_items: [
        { prompt: "What two things multiply to give momentum?", answer: "Mass and velocity." },
        { prompt: "Why does a heavier skater roll through rough patches better?", answer: "More momentum for the same speed." }
      ],
      checkpoint: { state: "practicing", reason: "worked examples unaided" }
    )

    ChatRecapJob.perform_now(@run)

    @topic.reload
    assert @topic.practicing?
    assert_equal "tutor", @topic.mastery_evidence
    assert_equal 2, @topic.review_items.count
    log = users(:one).study_logs.sole
    assert_equal "tutor", log.activity
    assert_equal subjects(:physics), log.subject
    assert @run.reload.items.grep(Note).one?
  end

  test "a hello-goodbye session is not evidence — no checkpoint moves" do
    @run.tool_run_messages.create!(role: :user, content: "hi")
    stub_recap(
      recap: { title: "Tutoring recap — momentum", body: "Barely started." },
      review_items: [],
      checkpoint: { state: "mastered", reason: "seemed fine" }
    )

    ChatRecapJob.perform_now(@run)

    assert @topic.reload.unseen?
  end

  test "without a syllabus tie the recap is the classic note and nothing else" do
    run = users(:one).tool_runs.create!(tool_slug: "tutor", inputs: { "topic" => "spanish" })
    run.tool_run_messages.create!(role: :user, content: "hola")
    stub_recap(recap: { title: "Tutoring recap — spanish", body: "Greetings covered." })

    ChatRecapJob.perform_now(run)

    assert run.reload.items.grep(Note).one?
    assert_empty users(:one).study_logs
    assert_empty users(:one).review_items
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
