require "test_helper"

class HobbiesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "create adds a hobby lens and returns to the Hobbies page" do
    assert_difference "Section.custom.count", 1 do
      post hobbies_path, params: { name: "Birdwatching" }
    end

    assert_redirected_to section_path("hobbies")
    lens = Section.find_by(slug: "birdwatching")
    assert_equal sections(:hobbies), lens.parent
  end

  test "create with a blank name explains instead of blowing up" do
    assert_no_difference "Section.count" do
      post hobbies_path, params: { name: "  " }
    end

    assert_redirected_to section_path("hobbies")
    assert_equal "A hobby needs a name.", flash[:alert]
  end

  test "create is idempotent for an existing lens" do
    Hobbies::Lens.find_or_create!("Guitar")

    assert_no_difference "Section.count" do
      post hobbies_path, params: { name: "guitar" }
    end
    assert_redirected_to section_path("hobbies")
  end

  test "destroy removes a custom lens; tagged items keep their other tags" do
    lens = Hobbies::Lens.find_or_create!("Guitar")
    task = users(:one).tasks.create!(title: "Practice scales")
    task.sections = [ lens, sections(:hobbies) ]
    grant = users(:one).granted_access_grants.create!(grantee: users(:two), subject: lens)

    delete hobby_path(lens)

    assert_redirected_to section_path("hobbies")
    assert_not Section.exists?(lens.id)
    assert_equal [ sections(:hobbies) ], task.reload.sections.to_a
    assert_not AccessGrant.exists?(grant.id)
  end

  test "seeded sections cannot be destroyed" do
    assert_no_difference "Section.count" do
      delete hobby_path(sections(:budget))
    end
    assert_response :not_found
  end
end
