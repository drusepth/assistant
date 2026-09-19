require "test_helper"

# Where a match shows and how it is corrected (D-event-radar): the chip and
# sentence on a row, the For-you filter, "Not this" and its Undo, the
# hobby page's nearby list, the two briefs — and the honest lines when no
# model is configured.
class RadarMatchSurfacesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @birding = Hobbies::Lens.find_or_create!("Birding")
    @place = users(:one).places.create!(name: "Tulsa")
    @source = @place.listing_sources.create!(url: "https://library.example/cal.ics", title: "Library")
    @walk = @source.happenings.create!(uid: "walk", title: "Fall bird walk", starts_at: 3.days.from_now)
    @council = @source.happenings.create!(uid: "council", title: "Council budget meeting", starts_at: 4.days.from_now)
    @match = HappeningMatch.create!(happening: @walk, target: "section:#{@birding.id}", section: @birding, reason: "a guided walk for birders")
  end

  test "the river leads with what's for you, with the chip and the sentence, and Everything is one click away" do
    get happenings_path

    assert_response :success
    assert_match "Fall bird walk", response.body
    assert_no_match "Council budget meeting", response.body
    assert_select ".chip[title=?]", "For Birding — a guided walk for birders", text: "Birding"
    assert_select "form[action=?]", reject_happening_path(@walk, target: @match.target)

    get happenings_path(all: 1)
    assert_match "Council budget meeting", response.body
  end

  test "Not this tombstones the match and Undo restores it" do
    patch reject_happening_path(@walk, target: @match.target), as: :turbo_stream

    assert_response :success
    assert @match.reload.rejected?
    assert_not @walk.reload.matched?
    assert_match "Undo not-this", response.body

    patch unreject_happening_path(@walk, target: @match.target)

    assert_not @match.reload.rejected?
  end

  test "a hobby's own page lists what's near you for it, and only for it" do
    get section_path(@birding.slug)

    assert_response :success
    assert_select "[data-hobby-nearby]"
    assert_match "Fall bird walk", response.body
    assert_no_match "Council budget meeting", response.body
    assert_select "[data-hobby-nearby] .chip", text: "for you"
  end

  test "the hub's Near-you card is what matched" do
    get section_path("hobbies")

    assert_select "[data-hobby-radar]"
    assert_match "Fall bird walk", response.body
    assert_no_match "Council budget meeting", response.body
  end

  test "with no model the filter is absent, everything shows, and the pages say why" do
    users(:one).household.model_profile.update!(api_key: "")
    @match.destroy!

    get happenings_path
    assert_match "Council budget meeting", response.body
    assert_no_match "For you", response.body
    assert_match "No model is configured", response.body

    get section_path(@birding.slug)
    assert_match "No model is configured, so nothing is matched to Birding", response.body
  end

  test "the briefs are saved from the Places page, and a change re-reads the recent past" do
    @walk.update!(matched_at: 1.day.ago)

    assert_enqueued_with(job: MatchHappeningsJob) do
      patch radar_brief_path, params: { radar_brief: "Farmers' markets and free concerts.", causes_brief: "Animals." }
    end

    assert_redirected_to places_path
    users(:one).reload
    assert_equal "Farmers' markets and free concerts.", users(:one).radar_brief
    assert_equal "Animals.", users(:one).causes_brief
    assert_nil @walk.reload.matched_at

    get places_path
    assert_match "Farmers&#39; markets and free concerts.", response.body
  end

  test "asking for a sentence enqueues one call, or says the model is missing" do
    assert_enqueued_with(job: AuthorRadarBriefJob) { post author_radar_brief_path(kind: "causes") }
    assert_match "Reading what you follow", flash[:notice]

    users(:one).household.model_profile.update!(api_key: "")
    post author_radar_brief_path(kind: "radar")
    assert_match "No model is configured", flash[:alert]
  end
end
