require "test_helper"

# The curriculum commons (D-curriculum-commons): every shipped course must
# parse, and enrolling copies an outline into a learner-owned tree.
class CurriculumCommonsTest < ActiveSupport::TestCase
  test "every course on the shelf parses with strands, topics, and summaries" do
    assert_operator Curriculum::Commons.all.size, :>=, 6

    Curriculum::Commons.all.each do |course|
      assert course.key.present?
      assert course.title.present?
      assert course.description.present?
      assert_operator course.strands.size, :>=, 3, "#{course.key} is too thin to be a course"
      course.strands.each do |strand|
        assert strand.topics.any?, "#{course.key} / #{strand.title} has no topics"
        strand.topics.each do |entry|
          assert entry.summary.present?, "#{course.key} / #{entry.title} doesn't say what mastering it means"
        end
      end
    end
  end

  test "match finds a course by title or key, and nothing for the long tail" do
    assert_equal "civics", Curriculum::Commons.match("Civics & how power works").key
    assert_equal "everyday-math", Curriculum::Commons.match("everyday math")&.key
    assert_nil Curriculum::Commons.match("Beekeeping for beginners")
  end

  test "enrolling instantiates a personal tree, stamped built" do
    subject = Curriculum::Commons.instantiate!("civics", user: users(:outsider), interest_frame: "evenings only")
    course = Curriculum::Commons.find!("civics")

    assert_equal users(:outsider), subject.user
    assert_equal "civics", subject.commons_key
    assert_equal "evenings only", subject.interest_frame
    assert subject.tree_built_at.present?
    assert_equal course.strands.size, subject.strands.count
    assert_equal course.topic_count, subject.leaf_count
    assert subject.leaf_topics.all? { |topic| topic.unseen? }
  end
end
