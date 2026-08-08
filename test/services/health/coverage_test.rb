require "test_helper"

class Health::CoverageTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "finds plan-shaped documents by title or summary keyword" do
    sbc = @user.documents.create!(title: "Acme PPO Summary of Benefits")
    eob = @user.documents.create!(title: "Letter from Acme", summary: "An explanation of benefits for the March visit.")
    @user.documents.create!(title: "Apartment lease")

    assert_equal [ eob, sbc ], Health::Coverage.documents(@user)
  end

  test "reads through the visibility wall — a spouse's shared plan counts, an unshared one doesn't" do
    shared = users(:two).documents.create!(title: "Family health insurance card")
    AccessGrant.create!(grantor: users(:two), grantee: @user, subject: shared)
    users(:two).documents.create!(title: "Bob's dental insurance policy")

    assert_equal [ shared ], Health::Coverage.documents(@user)
  end

  test "the owner's word beats the keywords: pinned leads, banished disappears" do
    banished = @user.documents.create!(title: "Car insurance policy", health_plan: false)
    pinned = @user.documents.create!(title: "Benefits booklet", health_plan: true, created_at: 1.year.ago)
    keyword = @user.documents.create!(title: "Acme SBC deductible summary")

    assert_equal [ pinned, keyword ], Health::Coverage.documents(@user)
    assert_not_includes Health::Coverage.documents(@user), banished
  end

  test "respects the limit, newest first" do
    older = @user.documents.create!(title: "Old insurance card", created_at: 2.years.ago)
    newer = @user.documents.create!(title: "New insurance card")

    assert_equal [ newer ], Health::Coverage.documents(@user, limit: 1)
    assert_equal [ newer, older ], Health::Coverage.documents(@user)
  end
end
