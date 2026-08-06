require "test_helper"

class SectionableTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
  end

  test "an item can be tagged with multiple sections" do
    event = @alice.events.create!(title: "Mom's cardiology appointment", starts_at: 1.week.from_now)
    event.sections << sections(:health)
    event.sections << sections(:money)

    assert_equal [ "health", "money" ], event.sections.map(&:slug).sort
  end

  test "in_section returns only items tagged with that section" do
    tagged = @alice.tasks.create!(title: "Dispute the bill")
    tagged.sections << sections(:disputes)
    untagged = @alice.tasks.create!(title: "Unrelated")

    assert_includes Task.in_section(sections(:disputes)), tagged
    assert_not_includes Task.in_section(sections(:disputes)), untagged
  end

  test "the same section cannot be tagged twice on one item" do
    task = @alice.tasks.create!(title: "Budget review")
    task.sections << sections(:money)

    assert_raises(ActiveRecord::RecordInvalid) do
      SectionTagging.create!(section: sections(:money), taggable: task)
    end
  end

  test "taggings are destroyed with their item" do
    task = @alice.tasks.create!(title: "Budget review")
    task.sections << sections(:money)

    assert_difference("SectionTagging.count", -1) { task.destroy! }
  end
end
