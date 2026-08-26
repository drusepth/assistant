require "test_helper"

class ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @item = users(:one).review_items.create!(
      topic: topics(:fractions_compare),
      prompt: "Which is bigger, 2/3 or 3/5?",
      answer: "2/3 — over fifteenths it's 10 vs 9."
    )
  end

  test "the queue shows one card with the honest quartet" do
    get reviews_path
    assert_response :success
    assert_match "Which is bigger", response.body
    assert_match "1 card due", response.body
    assert_match "10 min", response.body
  end

  test "grading schedules the card and the queue moves on" do
    post grade_review_path(@item, rating: :good)
    assert_redirected_to reviews_path

    assert @item.reload.review?
    assert_operator @item.due_at, :>, Time.current

    get reviews_path
    assert_match "All clear", response.body
  end

  test "each grade extends the day's measured study log" do
    post grade_review_path(@item, rating: :good)

    log = users(:one).study_logs.sole
    assert_equal "review", log.activity
    assert_equal subjects(:algebra), log.subject
    assert_operator log.minutes, :>=, 1
  end

  test "a decayed mastered topic goes rusty on queue load, and clean recall shores it up" do
    item = users(:one).review_items.create!(
      topic: topics(:percentages), prompt: "What's 15% of 80?",
      state: :review, stability: 2.0, difficulty: 5.0,
      due_at: 30.days.ago, last_reviewed_at: 40.days.ago, reps: 3
    )

    get reviews_path
    assert topics(:percentages).reload.rusty?, "the green tile stopped lying"
    assert_equal "quiz", topics(:percentages).mastery_evidence, "decay keeps the evidence"

    @item.destroy!
    post grade_review_path(item, rating: :good)
    assert topics(:percentages).reload.mastered?, "re-earned in minutes, same evidence door"
  end

  test "another member's cards are unreachable" do
    foreign = users(:two).review_items.create!(topic: topics(:bob_veto), prompt: "veto?")
    post grade_review_path(foreign, rating: :good)
    assert_response :not_found
  end
end
