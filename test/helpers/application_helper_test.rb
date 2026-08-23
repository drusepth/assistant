require "test_helper"

# The section picker is now a correction path rather than a filing chore
# (D16), so what it offers matters: a form that opens with every lens in the
# taxonomy is the thing this replaced, and a picker that quietly omits a tag
# the item already carries would delete it on save.
class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  setup do
    Current.session = users(:one).sessions.create!
    @recipe = users(:one).recipes.create!(title: "Lentil soup")
  end

  teardown { Current.session = nil }

  test "offers the sections this household turned on, and their subsections" do
    slugs = section_picker_choices(@recipe).map(&:slug)

    assert_includes slugs, "health"
    assert_includes slugs, "renting"
  end

  test "leaves out a section the user switched off" do
    users(:one).user_sections.create!(section: sections(:rights), enabled: false)

    slugs = section_picker_choices(@recipe).map(&:slug)

    assert_not_includes slugs, "rights"
    assert_not_includes slugs, "renting"
    assert_includes slugs, "health"
  end

  test "still offers a tag already applied from a section since switched off" do
    @recipe.sections << sections(:rights)
    users(:one).user_sections.create!(section: sections(:rights), enabled: false)

    assert_includes section_picker_choices(@recipe).map(&:slug), "rights"
  end

  test "the collapsed line names who did the filing" do
    assert_equal "your assistant files this one", section_picker_summary(@recipe)

    @recipe.sections << sections(:health)
    assert_equal "Health", section_picker_summary(@recipe.reload)
  end
end
