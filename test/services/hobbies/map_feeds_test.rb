require "test_helper"

# A new hobby is a question about every feed already followed, not just the
# ones parked in the catch-all (D-hobby-feeds §4).
class Hobbies::MapFeedsTest < ActiveJob::TestCase
  LLM = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @guitar = Hobbies::Lens.find_or_create!("Guitar")
    @other = Hobbies::OtherInterests.find_or_create!
  end

  test "a feed parked in the catch-all moves to the hobby that claims it" do
    feed = feed("https://example.com/luthier.xml", sections: [ @other ])
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    stub_picks(feed => [ "woodworking" ])

    assert_equal [ feed ], Hobbies::MapFeeds.call(@user, [ wood ])
    assert_equal [ wood ], feed.reload.sections.to_a, "the catch-all means 'no hobby' — it can't coexist with one"
  end

  # The point of asking about *every* feed: a lutherie blog filed under
  # Guitar belongs to Woodworking too, and a feed takes as many lenses as fit.
  test "a feed that already has a hobby can gain another" do
    feed = feed("https://example.com/luthier.xml", sections: [ @guitar ])
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    stub_picks(feed => [ "woodworking" ])

    Hobbies::MapFeeds.call(@user, [ wood ])

    assert_equal [ @guitar, wood ].sort_by(&:id), feed.reload.sections.sort_by(&:id)
  end

  test "mapping only ever adds, so a hand-made tag survives a model that disagrees" do
    feed = feed("https://example.com/luthier.xml", sections: [ @guitar ])
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    stub_picks({}) # the model claims nothing

    assert_empty Hobbies::MapFeeds.call(@user, [ wood ])
    assert_equal [ @guitar ], feed.reload.sections.to_a
  end

  # MapFeedsJob raised "Section has already been taken" in production.
  test "a slug the model names twice is one tag, not a duplicate" do
    feed = feed("https://example.com/luthier.xml", sections: [ @other ])
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    stub_picks(feed => [ "woodworking", "woodworking" ])

    assert_equal [ feed ], Hobbies::MapFeeds.call(@user, [ wood ])
    assert_equal [ wood ], feed.reload.sections.to_a
  end

  # An OPML import enqueues overlapping jobs; one can file a feed after the
  # other has already loaded it.
  test "a feed another job filed in the meantime is left alone" do
    feed = feed("https://example.com/luthier.xml", sections: [ @other ])
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    stale = @user.feeds.includes(:sections).find(feed.id)
    stale.sections.load
    Hobbies::OtherInterests.claim!(Feed.find(feed.id), wood)

    assert_empty Hobbies::OtherInterests.claim!(stale, wood)
    assert_equal [ wood ], feed.reload.sections.to_a
  end

  test "one question covers several new hobbies and several feeds" do
    wood_feed = feed("https://example.com/wood.xml", sections: [ @other ])
    bake_feed = feed("https://example.com/bake.xml", sections: [ @other ])
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    baking = Hobbies::Lens.find_or_create!("Baking")
    stub_picks(wood_feed => [ "woodworking" ], bake_feed => [ "baking" ])

    Hobbies::MapFeeds.call(@user, [ wood, baking ])

    assert_equal [ wood ], wood_feed.reload.sections.to_a
    assert_equal [ baking ], bake_feed.reload.sections.to_a
    assert_requested :post, LLM, times: 1
  end

  test "the model can only pick from the ids and slugs it was handed" do
    mine = feed("https://example.com/wood.xml", sections: [ @other ])
    theirs = users(:two).feeds.create!(url: "https://example.com/theirs.xml")
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    stub_body({ feeds: [
      { id: theirs.id, hobbies: [ "woodworking" ] },
      { id: mine.id, hobbies: [ "not-a-hobby", "hobbies" ] },
      { id: 0, hobbies: [ "woodworking" ] }
    ] })

    assert_empty Hobbies::MapFeeds.call(@user, [ wood ])
    assert_empty theirs.reload.sections, "somebody else's reading list is not this user's business"
    assert_equal [ @other ], mine.reload.sections.to_a
  end

  test "feeds are asked about in bounded chunks" do
    (Hobbies::MapFeeds::CHUNK + 1).times { |n| feed("https://example.com/#{n}.xml", sections: [ @other ]) }
    wood = Hobbies::Lens.find_or_create!("Woodworking")
    stub_picks({})

    Hobbies::MapFeeds.call(@user, [ wood ])

    assert_requested :post, LLM, times: 2
  end

  test "nothing to ask, nobody to ask, or nothing to ask about means no call at all" do
    wood = Hobbies::Lens.find_or_create!("Woodworking")

    assert_not Hobbies::MapFeeds.enqueue(@user, [ wood ]), "no feeds"

    feed("https://example.com/wood.xml", sections: [ @other ])
    assert Hobbies::MapFeeds.enqueue(@user, [ wood ])

    @user.household.model_profile.update!(api_key: "")
    assert_not Hobbies::MapFeeds.enqueue(@user, [ wood ]), "no model"

    @user.household.model_profile.update!(api_key: "test-key")
    assert_not Hobbies::MapFeeds.enqueue(@user, [ @other ]), "the catch-all is never something to map onto"
    assert_not_requested :post, LLM
  end

  private
    def feed(url, sections: [])
      @user.feeds.create!(url: url, sections: sections)
    end

    def stub_picks(picks)
      stub_body({ feeds: picks.map { |feed, slugs| { id: feed.id, hobbies: slugs } } })
    end

    def stub_body(payload)
      stub_request(:post, LLM).to_return(
        status: 200,
        body: { choices: [ { message: { content: payload.to_json } } ] }.to_json
      )
    end
end
