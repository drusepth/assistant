require "test_helper"

# The rule is a list of words the user owns (D-story-matching §4.1) — add
# one, remove one, on the hobby's own page, model or no model.
class WatchlistsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:one)
    @birding = Hobbies::Lens.find_or_create!("Birding")
  end

  test "adding a word saves it and re-reads the stories already here" do
    assert_enqueued_with(job: MatchStoriesJob) do
      post watchlist_terms_path, params: { section_id: @birding.id, term: "Warbler " }
    end

    assert_equal %w[ warbler ], watchlist.terms
  end

  test "a negative is its own list" do
    post watchlist_terms_path, params: { section_id: @birding.id, term: "records", kind: "negatives" }

    assert_equal %w[ records ], watchlist.negatives
    assert_empty watchlist.terms
  end

  test "removing a word takes it off the list" do
    post watchlist_terms_path, params: { section_id: @birding.id, term: "warbler" }
    delete watchlist_terms_path, params: { section_id: @birding.id, term: "warbler" }

    assert_empty watchlist.terms
  end

  test "something that isn't a word says so instead of saving nonsense" do
    post watchlist_terms_path, params: { section_id: @birding.id, term: "the" }

    assert_match(/word or a short phrase/, flash[:alert])
    assert_empty watchlist.terms
  end

  test "the kind is one of two, whatever the form says" do
    post watchlist_terms_path, params: { section_id: @birding.id, term: "warbler", kind: "dropped" }

    assert_equal %w[ warbler ], watchlist.terms, "an unknown list falls back to the words themselves"
  end

  # Other Interests is where a story lands when nothing claims it, so a rule
  # routing *into* it would mean nothing.
  test "the catch-all can't have a rule, and neither can a section that isn't a hobby" do
    post watchlist_terms_path, params: { section_id: Hobbies::OtherInterests.find_or_create!.id, term: "warbler" }
    assert_equal "That isn't a hobby.", flash[:alert]

    post watchlist_terms_path, params: { section_id: sections(:money).id, term: "warbler" }
    assert_equal "That isn't a hobby.", flash[:alert]
    assert_empty Watchlist.all
  end

  test "asking the model for words is an explicit request, and honest when there is no model" do
    assert_enqueued_with(job: AuthorWatchlistJob) do
      post watchlist_author_path, params: { section_id: @birding.id }
    end
    assert_match(/Reading your feeds/, flash[:notice])

    users(:one).household.model_profile.update!(api_key: "")
    post watchlist_author_path, params: { section_id: @birding.id }
    assert_match(/yours to type/, flash[:alert])
  end

  test "a paused feed can be watched again" do
    feed = users(:one).feeds.create!(url: "https://example.com/news.xml")
    list = Watchlist.create!(user: users(:one), section: @birding, terms: %w[ bird ])
    list.suspend!(feed, reason: "bird")

    post watchlist_resume_path, params: { section_id: @birding.id, feed_id: feed.id }

    assert_empty list.reload.suspended_feed_ids
    assert_match(/watching/, flash[:notice])
  end

  test "one member cannot write another's rule" do
    theirs = users(:two)
    Watchlist.create!(user: theirs, section: @birding, terms: %w[ heron ])

    post watchlist_terms_path, params: { section_id: @birding.id, term: "warbler" }

    assert_equal %w[ heron ], Watchlist.find_by(user: theirs, section: @birding).terms
    assert_equal %w[ warbler ], watchlist.terms
  end

  private
    def watchlist = Watchlist.find_by!(user: users(:one), section: @birding)
end
