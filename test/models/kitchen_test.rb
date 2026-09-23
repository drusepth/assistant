require "test_helper"

class KitchenTest < ActiveSupport::TestCase
  test "private until shared, and a share lets the grantee cook" do
    kitchen = users(:one).kitchens.create!(name: "Home")

    assert kitchen.cookable_by?(users(:one))
    assert_not kitchen.cookable_by?(users(:two))

    users(:one).granted_access_grants.create!(grantee: users(:two), subject: kitchen)

    assert kitchen.cookable_by?(users(:two))
    assert_not kitchen.owned_by?(users(:two))
  end

  test "can't be shared outside the household" do
    kitchen = users(:one).kitchens.create!(name: "Home")
    grant = users(:one).granted_access_grants.new(grantee: users(:outsider), subject: kitchen)

    assert_not grant.valid?
  end
end
