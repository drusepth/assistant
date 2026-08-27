require "test_helper"

# What the "Add another hobby" tile offers (D-hobby-spotting): this
# household's own reading first, the broad starter names after.
class Hobbies::SuggestionsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @hobbies = Section.find_by!(slug: "hobbies")
  end

  test "spotted names lead, starters fill, and a hobby you already have is neither" do
    spot("Birding", "Two of your feeds are about birds.")
    Hobbies::Lens.find_or_create!("Baking")

    chips = Hobbies::Suggestions.for(@user, @hobbies.reload, limit: 4)

    assert_equal "Birding", chips.first.name
    assert chips.first.spotted?
    assert_equal "Two of your feeds are about birds.", chips.first.reason
    assert_not chips.second.spotted?, "everything after the spotted names is the starter list"
    assert_not_includes chips.map(&:name), "Baking"
  end

  test "a name the user already made a hobby of stops being suggested" do
    spot("Birding")
    Hobbies::Lens.find_or_create!("birding")

    assert_not_includes Hobbies::Suggestions.for(@user, @hobbies.reload).map(&:name), "Birding"
  end

  # One refusal, both surfaces: dismissing the nudge quiets the chip too.
  test "a spotted name whose nudge was dismissed is quiet for the rest of the month" do
    spot("Birding")
    @user.suggestions.create!(
      watcher_slug: "hobby_from_feeds", title: "Looks like Birding is a thing",
      fingerprint: Watcher::HobbyFromFeeds.fingerprint_for("Birding"), status: :dismissed
    )

    assert_not_includes Hobbies::Suggestions.for(@user, @hobbies).map(&:name), "Birding"
  end

  test "with nothing spotted the chips are the starter list, in its own order" do
    assert_equal Hobbies::Suggestions::STARTERS.first(4),
      Hobbies::Suggestions.for(@user, @hobbies, limit: 4).map(&:name)
  end

  private
    def spot(name, reason = nil)
      @user.spotted_hobbies.create!(name: name, reason: reason, feed_ids: [], position: 0)
    end
end
