require "test_helper"

# "Quiz me on this" on a note (D-note-quiz): the retrieval gate pointed at
# the notes. A plain note is its own material; a note a quiz filed is a
# report card that points past itself at what the quiz was really about.
class QuizNoteToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @note = @user.notes.create!(title: "Sourdough starter", body: "Feed 1:1:1 by weight; peak at 4–6 hours at 24°C.")
  end

  test "the opening question is asked from the note's own words" do
    stub_chat("Three questions on your sourdough note. First: what's the feeding ratio?")

    ToolRunJob.perform_now(quiz_on(@note))

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Feed 1:1:1 by weight") && request.body.include?("Sourdough starter")
    end
  end

  test "finishing a plain note quiz files a recap filed where the note is" do
    @note.sections = [ sections(:hobbies) ]
    run = quiz_on(@note)
    run.tool_run_messages.create!(role: :assistant, content: "What's the feeding ratio?")
    run.tool_run_messages.create!(role: :user, content: "1:1:1 by weight.")
    stub_recap(recap: { title: "Quiz — sourdough starter", body: "Ratio cold, timing shaky." })

    ChatRecapJob.perform_now(run)

    recap = run.reload.items.grep(Note).sole
    assert_match(/Ratio cold/, recap.body)
    assert_equal [ sections(:hobbies) ], recap.sections.to_a
    # Nothing in the syllabus to move, and no hours to log.
    assert_empty @user.study_logs
    assert_empty @user.review_items
  end

  test "a quiz recap points past itself: the topic and the misses, never its own prose" do
    stub_chat("Second pass on comparing fractions. First: which is bigger, 5/8 or 3/5?")

    ToolRunJob.perform_now(quiz_on(quiz_me_recap))

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Comparing unlike denominators") &&
        request.body.include?("Which is bigger: 1 1/3 or 4/3?") &&
        request.body.include?("never quiz its prose")
    end
  end

  test "finishing a re-quiz is evidence in the syllabus like any other" do
    run = quiz_on(quiz_me_recap)
    run.tool_run_messages.create!(role: :user, content: "5/8 — 25/40 against 24/40.")
    stub_recap(
      recap: { title: "Quiz — comparing fractions", body: "Better than last time." },
      verdict: { state: "mastered", reason: "answered everything" },
      missed: [ { prompt: "Which is bigger: 7/9 or 5/7?", answer: "7/9." } ]
    )

    ChatRecapJob.perform_now(run)

    topic = topics(:fractions_compare).reload
    assert topic.mastered?
    assert_equal "quiz", topic.mastery_evidence
    assert_includes topic.review_items.pluck(:prompt), "Which is bigger: 7/9 or 5/7?"
    assert_equal "review", @user.study_logs.sole.activity
  end

  test "a quiz on a note-quiz recap walks back to the note the material lives in" do
    first = quiz_on(@note)
    recap = @user.notes.create!(title: "Quiz — sourdough starter", body: "Ratio cold, timing shaky.")
    first.tool_run_items.create!(item: recap)
    stub_chat("Second pass. What's the feeding ratio?")

    ToolRunJob.perform_now(quiz_on(recap))

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Feed 1:1:1 by weight") && request.body.include?("never quiz its prose")
    end
  end

  test "a recap whose material is gone is quizzed as an ordinary note" do
    orphan = @user.notes.create!(title: "Quiz — something", body: "It went fine.")
    @user.tool_runs.create!(tool_slug: "quiz_me", inputs: { "topic_id" => "0" })
      .tool_run_items.create!(item: orphan)
    stub_chat("One question on that note.")

    ToolRunJob.perform_now(quiz_on(orphan))

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("The note to quiz them on") && !request.body.include?("never quiz its prose")
    end
  end

  test "a note unshared since the quiz started fails the run rather than quizzing on nothing" do
    theirs = users(:two).notes.create!(body: "Shared study material.")
    grant = theirs.access_grants.create!(grantor: users(:two), grantee: @user)
    run = quiz_on(theirs)
    grant.destroy!
    stub_chat("hello")

    ToolRunJob.perform_now(run)

    assert run.reload.failed?
    assert_match(/gone or no longer shared/, run.error)
  end

  test "another member's unshared note is unreachable" do
    theirs = users(:two).notes.create!(body: "Private.")
    run = @user.tool_runs.create!(tool_slug: "quiz_note", subject: theirs)
    stub_chat("hello")

    ToolRunJob.perform_now(run)

    assert run.reload.failed?
  end

  private
    def quiz_on(note)
      @user.tool_runs.create!(tool_slug: "quiz_note", subject: note)
    end

    # A note the Education quiz filed, with the cards it minted from the
    # misses — the shape a "quiz me on this recap" click starts from.
    def quiz_me_recap
      topic = topics(:fractions_compare)
      run = @user.tool_runs.create!(tool_slug: "quiz_me", inputs: { "topic_id" => topic.id.to_s })
      note = @user.notes.create!(title: "Quiz — comparing fractions", body: "One slip on mixed numbers.")
      run.tool_run_items.create!(item: note)
      card = @user.review_items.create!(topic: topic, kind: :flash,
        prompt: "Which is bigger: 1 1/3 or 4/3?", answer: "They're equal.")
      run.tool_run_items.create!(item: card)
      note
    end

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
