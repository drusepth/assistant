require "test_helper"

class Kitchens::CurrentTest < ActiveSupport::TestCase
  test "a first visit makes Home" do
    assert_difference -> { users(:one).kitchens.count } do
      assert_equal "Home", Kitchens::Current.for(users(:one)).name
    end
    assert_no_difference("Kitchen.count") { Kitchens::Current.for(users(:one)) }
  end

  test "a partner's shared kitchen in use beats my own empty one" do
    mine = users(:two).kitchens.create!(name: "Home", updated_at: 2.days.ago)
    theirs = users(:one).kitchens.create!(name: "Home", updated_at: 1.hour.ago)
    users(:one).granted_access_grants.create!(grantee: users(:two), subject: theirs)

    assert_equal theirs, Kitchens::Current.for(users(:two))

    users(:two).update!(current_kitchen: mine)
    assert_equal mine, Kitchens::Current.for(users(:two)), "an explicit pick wins"
  end

  test "a pick I can no longer see is ignored" do
    theirs = users(:one).kitchens.create!(name: "Home")
    users(:two).update!(current_kitchen: theirs)

    assert_not_equal theirs, Kitchens::Current.for(users(:two))
  end
end
