require "test_helper"

class HobbiesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { sign_in_as users(:one) }

  test "create adds a hobby lens and returns to the Hobbies page" do
    assert_difference "Section.custom.count", 1 do
      post hobbies_path, params: { name: "Birdwatching" }
    end

    assert_redirected_to section_path("hobbies")
    lens = Section.find_by(slug: "birdwatching")
    assert_equal sections(:hobbies), lens.parent
  end

  # The chip is worth more than typing the name because the attribution is
  # already made: the feeds move in this request, no model call (D-hobby-spotting).
  test "creating a hobby the spotter named moves the feeds it stood on" do
    other = Hobbies::OtherInterests.find_or_create!
    feeds = 2.times.map do |n|
      users(:one).feeds.create!(url: "https://example.com/birds#{n}.xml", sections: [ other ])
    end
    stray = users(:one).feeds.create!(url: "https://example.com/news.xml", sections: [ other ])
    users(:one).spotted_hobbies.create!(name: "Birding", reason: "Birds.", feed_ids: feeds.map(&:id))

    post hobbies_path, params: { name: "Birding" }

    lens = Section.find_by!(slug: "birding")
    assert_equal [ lens ], feeds.first.reload.sections.to_a
    assert_equal [ other ], stray.reload.sections.to_a
    assert_equal "Birding added to your hobbies, with 2 feeds moved over.", flash[:notice]
    assert_empty users(:one).spotted_hobbies.reload
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
    # What the hobby meant and what the model filed under it: both point at
    # the lens by foreign key, and a lens with either used to be undeletable.
    brief = users(:one).hobby_briefs.create!(section: lens, description: "Acoustic guitar, not the band")
    story = users(:one).feeds.create!(url: "https://example.com/music.xml")
      .feed_items.create!(guid: "g1", title: "A new luthier")
    routing = StoryRouting.create!(feed_item: story, section: lens, reason: "guitar building")

    delete hobby_path(lens)

    assert_redirected_to section_path("hobbies")
    assert_not Section.exists?(lens.id)
    assert_equal [ sections(:hobbies) ], task.reload.sections.to_a
    assert_not AccessGrant.exists?(grant.id)
    assert_not HobbyBrief.exists?(brief.id)
    assert_not StoryRouting.exists?(routing.id)
    assert FeedItem.exists?(story.id), "the story itself is not the hobby's to delete"
  end

  # D-hobby-feeds §4: hobbies arrive over months, so a new one is a question
  # about every feed already followed.
  test "a new hobby asks which of the feeds you already follow belong to it" do
    users(:one).feeds.create!(url: "https://example.com/wood.xml")

    assert_enqueued_with(job: MapFeedsJob) { post hobbies_path, params: { name: "Woodworking" } }
  end

  test "with no feeds, or no model, a new hobby asks nobody anything" do
    assert_no_enqueued_jobs(only: MapFeedsJob) { post hobbies_path, params: { name: "Woodworking" } }

    users(:one).feeds.create!(url: "https://example.com/wood.xml")
    users(:one).household.model_profile.update!(api_key: "")
    assert_no_enqueued_jobs(only: MapFeedsJob) { post hobbies_path, params: { name: "Baking" } }
  end

  # Taggings cascade with the section, so removing a hobby can leave a feed
  # with no lens at all — and the hub rests on every feed having one.
  test "removing a hobby drops its feeds into the catch-all rather than stranding them" do
    lens = Hobbies::Lens.find_or_create!("Guitar")
    other_hobby = Hobbies::Lens.find_or_create!("Baking")
    stranded = users(:one).feeds.create!(url: "https://example.com/guitar.xml", sections: [ lens ])
    kept = users(:one).feeds.create!(url: "https://example.com/both.xml", sections: [ lens, other_hobby ])

    delete hobby_path(lens)

    assert_equal [ Hobbies::OtherInterests.find ], stranded.reload.sections.to_a
    assert_equal [ other_hobby ], kept.reload.sections.to_a, "a feed that still has a hobby is left alone"
  end

  test "seeded sections cannot be destroyed" do
    assert_no_difference "Section.count" do
      delete hobby_path(sections(:budget))
    end
    assert_response :not_found
  end
end
