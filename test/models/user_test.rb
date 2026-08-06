require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "sections are enabled by default" do
    assert users(:one).section_enabled?(sections(:health))
    assert_includes users(:one).enabled_sections, sections(:health)
  end

  test "a section can be toggled off per user" do
    users(:one).user_sections.create!(section: sections(:health), enabled: false)

    assert_not users(:one).section_enabled?(sections(:health))
    assert_not_includes users(:one).enabled_sections, sections(:health)
    assert users(:two).section_enabled?(sections(:health))
  end

  test "enabled_sections follows the user's saved order, then taxonomy order" do
    users(:one).user_sections.create!(section: sections(:money), position: 1)
    users(:one).user_sections.create!(section: sections(:rights), position: 2)

    assert_equal [ sections(:money), sections(:rights), sections(:health) ],
      users(:one).enabled_sections.first(3)
    assert_equal sections(:health), users(:two).enabled_sections.first
  end

  test "destroying a user removes their data but not the household" do
    user = users(:one)
    user.tasks.create!(title: "Task")
    household = user.household

    assert_difference("Task.count", -1) { user.destroy! }
    assert household.reload.persisted?
  end
end
