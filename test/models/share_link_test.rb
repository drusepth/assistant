require "test_helper"

# The one sharing path that leaves the household (D-share-link): narrow on
# purpose — an allowlisted subject the owner owns, an unguessable token, and
# deletion as the revoke.
class ShareLinkTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @bob = users(:two)
    @recipe = @alice.recipes.create!(title: "Lentil soup")
  end

  test "mints a long unguessable token" do
    link = @alice.share_links.create!(subject: @recipe)

    assert_equal 24, link.token.length
    assert_not_equal link.token, @alice.share_links.create!(subject: @recipe).token
  end

  test "only the owner of the subject can hold the link" do
    link = @bob.share_links.new(subject: @recipe)

    assert_not link.valid?
    assert_includes link.errors[:subject], "must be yours to share"
  end

  test "the subject type is allowlisted" do
    note = @alice.notes.create!(body: "Not for the public")
    link = @alice.share_links.new(subject: note)

    assert_not link.valid?
    assert_includes link.errors[:subject_type], "is not included in the list"
  end

  test "live excludes expired links, and expiry is evaluated at request time" do
    live = @alice.share_links.create!(subject: @recipe)
    expiring = @alice.share_links.create!(subject: @recipe, expires_at: 1.hour.from_now)
    expired = @alice.share_links.create!(subject: @recipe, expires_at: 1.hour.ago)

    assert_equal [ live, expiring ].map(&:id).sort, ShareLink.live.pluck(:id).sort
    assert expired.expired?

    travel 2.hours do
      assert_equal [ live.id ], ShareLink.live.pluck(:id)
    end
  end

  test "expiry choices become timestamps, and 'never' stays nil" do
    assert_nil ShareLink.expiry_from("")
    assert_in_delta 7.days.from_now.to_f, ShareLink.expiry_from("7").to_f, 5
  end

  test "views are counted without touching updated_at" do
    link = @alice.share_links.create!(subject: @recipe)
    before = link.updated_at

    link.record_view!

    assert_equal 1, link.reload.views_count
    assert_not_nil link.last_viewed_at
    assert_equal before.to_i, link.updated_at.to_i
  end

  test "deleting the recipe takes its links with it" do
    @alice.share_links.create!(subject: @recipe)

    assert_difference "ShareLink.count", -1 do
      @recipe.destroy!
    end
  end
end
