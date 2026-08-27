require "test_helper"

# A sentence and a switch (D-story-matching §4) — the whole surface the user
# has over routing, and it works with or without a model.
class HobbyBriefsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:one)
    @birding = Hobbies::Lens.find_or_create!("Birding")
  end

  test "writing what the hobby means saves it" do
    patch hobby_brief_path, params: { section_id: @birding.id,
      description: "  Local birds and optics — not the band.  " }

    assert_equal "Local birds and optics — not the band.", brief.description
    assert_predicate brief, :enabled?
  end

  test "switching a hobby off stops it being offered, and back on re-reads the recent past" do
    patch hobby_brief_path, params: { section_id: @birding.id, enabled: "0" }
    assert_not brief.enabled?
    assert_empty HobbyBrief.routable_sections(users(:one)).select { |s| s == @birding }

    assert_enqueued_with(job: RouteStoriesJob) do
      patch hobby_brief_path, params: { section_id: @birding.id, enabled: "1" }
    end
    assert_predicate brief, :enabled?
  end

  test "a sentence longer than the box is refused out loud, not truncated silently" do
    patch hobby_brief_path, params: { section_id: @birding.id, description: "x" * 700 }

    assert_response :redirect
    assert_match(/too long/i, flash[:alert])
    assert_nil HobbyBrief.find_by(user: users(:one), section: @birding)&.description
  end

  # Other Interests is where a story lands when nothing claims it, so a
  # brief routing *into* it would mean nothing.
  test "the catch-all can't have a brief, and neither can a section that isn't a hobby" do
    patch hobby_brief_path, params: { section_id: Hobbies::OtherInterests.find_or_create!.id, description: "no" }
    assert_equal "That isn't a hobby.", flash[:alert]

    patch hobby_brief_path, params: { section_id: sections(:money).id, description: "no" }
    assert_equal "That isn't a hobby.", flash[:alert]
    assert_empty HobbyBrief.all
  end

  test "asking the model for a sentence is an explicit request, and honest when there is no model" do
    assert_enqueued_with(job: AuthorBriefJob) do
      post author_hobby_brief_path, params: { section_id: @birding.id }
    end
    assert_match(/Reading your feeds/, flash[:notice])

    users(:one).household.model_profile.update!(api_key: "")
    post author_hobby_brief_path, params: { section_id: @birding.id }
    assert_match(/yours to write/, flash[:alert])
  end

  test "one member cannot write another's brief" do
    HobbyBrief.create!(user: users(:two), section: @birding, description: "Theirs.")

    patch hobby_brief_path, params: { section_id: @birding.id, description: "Mine." }

    assert_equal "Theirs.", HobbyBrief.find_by(user: users(:two), section: @birding).description
    assert_equal "Mine.", brief.description
  end

  private
    def brief = HobbyBrief.find_by!(user: users(:one), section: @birding).reload
end
