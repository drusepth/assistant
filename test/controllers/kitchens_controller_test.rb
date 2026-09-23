require "test_helper"

class KitchensControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the Food hub opens on a kitchen and asks once whether to share it" do
    get section_path("food")
    assert_response :success
    kitchen = users(:one).kitchens.sole
    assert_match "Share this kitchen with Bob Smith?", response.body

    post answer_share_kitchen_path(kitchen, share: "everyone")
    assert_redirected_to food_path
    assert kitchen.reload.cookable_by?(users(:two))

    get section_path("food")
    assert_no_match "Share this kitchen with", response.body
  end

  test "keeping it private answers the question without sharing" do
    kitchen = users(:one).kitchens.create!(name: "Home")

    post answer_share_kitchen_path(kitchen, share: "none")

    assert_not kitchen.reload.share_prompt_pending?
    assert_not kitchen.cookable_by?(users(:two))
  end

  test "settings, rename, a second kitchen, switching, and delete" do
    kitchen = users(:one).kitchens.create!(name: "Home")
    get edit_kitchen_path(kitchen)
    assert_response :success
    assert_match "can add to its lists", response.body

    patch kitchen_path(kitchen), params: { kitchen: { name: "Flat" } }
    assert_equal "Flat", kitchen.reload.name

    assert_difference("Kitchen.count") { post kitchens_path, params: { kitchen: { name: "Cabin" } } }
    cabin = Kitchen.last
    assert_equal cabin, users(:one).reload.current_kitchen

    patch select_kitchen_path(kitchen)
    assert_equal kitchen, users(:one).reload.current_kitchen

    assert_difference("Kitchen.count", -1) { delete kitchen_path(cabin) }
  end

  test "a cook can't rename, delete or re-share someone else's kitchen" do
    theirs = users(:two).kitchens.create!(name: "Bob's")
    users(:two).granted_access_grants.create!(grantee: users(:one), subject: theirs)

    get edit_kitchen_path(theirs)
    assert_response :success

    patch kitchen_path(theirs), params: { kitchen: { name: "Mine now" } }
    assert_response :not_found
    delete kitchen_path(theirs)
    assert_response :not_found
    assert_equal "Bob's", theirs.reload.name
  end

  test "a kitchen nobody shared is invisible" do
    theirs = users(:two).kitchens.create!(name: "Bob's")

    get edit_kitchen_path(theirs)
    assert_response :not_found
  end
end
