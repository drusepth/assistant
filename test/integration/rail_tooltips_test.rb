require "test_helper"

# The rail is drawn by the layout on every page, so this is the end of the
# wire the helper tests can't see: that the signals reach the tooltip
# attributes on a real render, and that the rows which must stay silent do.
class RailTooltipsTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "the rail hands each row what is behind it, and nothing where nothing is" do
    task = @user.tasks.create!(title: "Send the appeal", due_on: 2.days.ago)
    task.sections << sections(:career)
    @user.notes.create!(body: "Fresh thought")

    get root_url
    assert_response :success

    assert_select "a[href=?]", section_path("career") do |links|
      assert_equal "1 open task", links.first["data-tooltip-detail-value"]
      assert_equal "Overdue", links.first["data-tooltip-badge-value"]
      assert_equal "Career", links.first["aria-label"]
    end
    assert_select "a[href=?]", notes_path do |links|
      assert_equal "1 note · 1 this week", links.first["data-tooltip-detail-value"]
    end
    # Health has nothing in it, so its tooltip is a bare name.
    assert_select "a[href=?]", section_path("health") do |links|
      assert_nil links.first["data-tooltip-detail-value"]
      assert_equal "Health", links.first["data-tooltip-title-value"]
    end
  end

  test "the sealed containers never say how full they are" do
    get root_url

    [ credentials_path, diary_entries_path ].each do |path|
      assert_select "a[href=?]", path do |links|
        assert_nil links.first["data-tooltip-detail-value"], "#{path} leaked its contents"
        assert_nil links.first["data-tooltip-badge-value"], "#{path} leaked its contents"
      end
    end
  end

  test "no row still advertises a keyboard shortcut nothing binds" do
    get root_url

    assert_select "[data-tooltip-shortcut-value]", false
    assert_select "[data-tooltip-subtitle-value]", false
  end
end
