require "test_helper"

class LifeSectionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "lists every top-level section as a card with its blurb" do
    get life_sections_path
    assert_response :success

    Section.top_level.each do |section|
      assert_select "##{ActionView::RecordIdentifier.dom_id(section, :picker)}"
    end
    assert_match "The letters people otherwise pay a lawyer to write.", response.body
  end

  test "turning a section off hides it from the sidebar and deletes nothing" do
    rights = sections(:rights)

    patch life_section_path(rights.slug), params: { enabled: "0" }
    assert_redirected_to life_sections_path
    assert_not users(:one).section_enabled?(rights)

    follow_redirect!
    assert_select "nav a[href=?]", section_path(rights.slug), count: 0
    assert_select "button[aria-label=?]", "Turn on Rights"
  end

  test "turning a section back on returns it to the sidebar" do
    rights = sections(:rights)
    users(:one).user_sections.create!(section: rights, enabled: false)

    patch life_section_path(rights.slug), params: { enabled: "1" }
    assert users(:one).section_enabled?(rights)

    follow_redirect!
    assert_select "nav a[href=?]", section_path(rights.slug)
  end

  test "keeps the agent dial and order when toggled" do
    money = sections(:money)
    users(:one).user_sections.create!(section: money, agent_level: "active", position: 1)

    patch life_section_path(money.slug), params: { enabled: "0" }
    patch life_section_path(money.slug), params: { enabled: "1" }

    preference = users(:one).user_sections.find_by(section: money)
    assert_equal "active", preference.agent_level
    assert_equal 1, preference.position
  end

  test "only top-level sections can be toggled here" do
    patch life_section_path("budget"), params: { enabled: "0" }
    assert_response :not_found
  end

  test "the sidebar links to the picker" do
    get root_path
    assert_select "nav a[href=?]", life_sections_path
  end
end
