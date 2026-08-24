require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "work_summary composes what's stated and is nil when nothing is (D-work-profile)" do
    assert_equal "Cashier at Costco", User.new(job_title: "Cashier", employer: "Costco").work_summary
    assert_equal "Cashier", User.new(job_title: "Cashier").work_summary
    assert_equal "at Costco", User.new(employer: "Costco").work_summary
    assert_nil User.new.work_summary
    # Whitespace-only fields normalize to nothing stated.
    assert_nil User.new(job_title: "  ", employer: " ").work_summary
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

  test "initials fall back to the first letters of the first two words" do
    assert_equal "AS", users(:one).initials
    assert_equal "M", User.new(name: "madonna").initials
    assert_equal "AÉ", User.new(name: "ana école").initials
    assert_equal "", User.new(name: nil).initials
  end

  test "an avatar has to be an image the app can actually render" do
    user = users(:one)
    user.avatar.attach(io: file_fixture("sample.txt").open, filename: "sample.txt", content_type: "text/plain")

    assert_not user.valid?
    assert_match "PNG, JPEG, WEBP, or GIF", user.errors.full_messages.to_sentence
  end

  test "an oversized avatar is refused" do
    user = users(:one)
    user.avatar.attach(io: file_fixture("photo.jpg").open, filename: "photo.jpg", content_type: "image/jpeg")
    user.avatar.blob.update!(byte_size: User::AVATAR_MAX_BYTES + 1)

    assert_not user.valid?
    assert_match "bigger than", user.errors.full_messages.to_sentence
  end

  test "avatar_ready? is false until a variable image is attached" do
    user = users(:one)
    assert_not user.avatar_ready?

    user.avatar.attach(io: file_fixture("photo.jpg").open, filename: "photo.jpg", content_type: "image/jpeg")
    assert user.avatar_ready?
  end

  test "destroying a user removes their data but not the household" do
    user = users(:one)
    user.tasks.create!(title: "Task")
    household = user.household

    assert_difference("Task.count", -1) { user.destroy! }
    assert household.reload.persisted?
  end
end
