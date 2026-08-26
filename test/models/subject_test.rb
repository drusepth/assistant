require "test_helper"

class SubjectTest < ActiveSupport::TestCase
  test "mastery counts run over leaves, never strands" do
    counts = subjects(:algebra).mastery_counts

    assert_equal({ practicing: 1, unseen: 1, mastered: 1 }, counts)
    assert_equal 3, subjects(:algebra).leaf_count
  end

  test "current topic prefers what's being worked, then the next unseen" do
    assert_equal topics(:fractions_compare), subjects(:algebra).current_topic

    topics(:fractions_compare).update!(mastery: :mastered)
    assert_equal topics(:fractions_arithmetic), subjects(:algebra).reload.current_topic
  end

  test "rusty topics surface" do
    assert_equal [ topics(:friction) ], subjects(:physics).rusty_topics
  end

  test "private by default, visible through a grant" do
    refute subjects(:bob_civics).visible_to?(users(:one))

    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: subjects(:bob_civics))
    assert subjects(:bob_civics).visible_to?(users(:one))
    refute subjects(:bob_civics).visible_to?(users(:outsider))
  end

  test "pace compares mastered share to elapsed share of the learner's own runway" do
    subject = subjects(:algebra)
    subject.update!(created_at: 10.days.ago, target_date: 90.days.from_now.to_date)
    assert_equal :on_pace, subject.pace

    subject.update!(target_date: 12.days.from_now.to_date)
    assert_equal :behind, subject.pace

    subject.update!(target_date: nil)
    assert_nil subject.pace
  end

  test "advance! stamps evidence and the date; rusty keeps both" do
    topic = topics(:fractions_compare)
    topic.advance!(to: :mastered, evidence: "quiz")

    assert topic.mastered?
    assert_equal "quiz", topic.mastery_evidence
    assert_equal Date.current, topic.mastered_on

    topic.advance!(to: :rusty, evidence: "quiz")
    assert topic.rusty?
    assert_equal Date.current, topic.mastered_on, "the history is the record"
  end

  test "building_tree? is stamped away even on failure and never true for commons subjects" do
    refute subjects(:algebra).building_tree?

    generated = users(:one).subjects.create!(title: "Bird identification")
    assert generated.building_tree?

    generated.update_column(:tree_built_at, Time.current)
    refute generated.reload.building_tree?
  end
end
