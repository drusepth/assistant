require "test_helper"

class SectionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "shows visible items tagged with the section or its subsections" do
    mine = users(:one).tasks.create!(title: "Review budget")
    mine.sections << sections(:budget)
    other = users(:two).tasks.create!(title: "Bob money thing")
    other.sections << sections(:money)

    get section_path("money")
    assert_response :success
    assert_match "Review budget", response.body
    assert_no_match "Bob money thing", response.body
  end

  test "404s on an unknown section" do
    get section_path("nonsense")
    assert_response :not_found
  end

  test "shows the section's tools, including subsection tools on the parent page" do
    get section_path("rights")
    assert_response :success
    assert_match "Draft a dispute letter", response.body

    get section_path("disputes")
    assert_match "Draft a dispute letter", response.body
  end

  test "a section with no tools shows none" do
    get section_path("health")
    assert_response :success
    assert_no_match "Draft a dispute letter", response.body
  end

  test "education leads with the learn-something tool" do
    get section_path("education")
    assert_response :success
    assert_match "Learn something", response.body
  end

  test "the empty state offers capture pre-tagged with the section" do
    get section_path("health")
    assert_response :success
    assert_match "Nothing in Health yet", response.body
    assert_match new_task_path(section_ids: [ sections(:health).id ]), response.body
  end
end
