require "test_helper"

# Volunteer openings (D-listing-feeds §4.6): an undated role that is
# looking for people, read from a JobPosting marked VOLUNTEER, judged
# against the causes brief, shown on the People hub, landed as a task.
class OpeningsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @place = users(:one).places.create!(name: "Tulsa")
    @source = @place.listing_sources.create!(url: "https://spca.example/volunteer", kind: "page", title: "Tulsa SPCA")
  end

  test "a JobPosting marked VOLUNTEER parses as an opening with its closing date and organization" do
    html = <<~HTML
      <script type="application/ld+json">[
        {"@type":"JobPosting","title":"Weekend dog walker","employmentType":"VOLUNTEER","url":"https://spca.example/walk",
         "description":"Walk shelter dogs <b>Saturday</b> mornings.","validThrough":"2026-12-31T00:00:00",
         "hiringOrganization":{"@type":"Organization","name":"Tulsa SPCA"},
         "jobLocation":{"@type":"Place","address":{"@type":"PostalAddress","addressLocality":"Tulsa"},"geo":{"latitude":36.13,"longitude":-95.95}}},
        {"@type":"JobPosting","title":"Paid kennel tech","employmentType":"FULL_TIME","url":"https://spca.example/job"}
      ]</script>
    HTML

    items = Listings::Parse::Schema.call(html)

    role = items.sole
    assert role.opening?
    assert_equal "Weekend dog walker", role.title
    assert_equal "Walk shelter dogs Saturday mornings.", role.description
    assert_equal "Tulsa SPCA — Tulsa", role.location
    assert_equal Date.new(2026, 12, 31), role.expires_on
    assert_nil role.starts_at
    assert_in_delta 36.13, role.latitude
  end

  test "the river has an Openings pile, and an opening lands as a task" do
    role = @source.happenings.create!(uid: "walk", kind: "opening", title: "Weekend dog walker", location: "Tulsa SPCA")
    @source.happenings.create!(uid: "gala", title: "Adoption gala", starts_at: 5.days.from_now)
    users(:one).household.model_profile.update!(api_key: "")

    get happenings_path(kind: "opening")

    assert_response :success
    assert_match "Weekend dog walker", response.body
    assert_no_match "Adoption gala", response.body
    assert_match "Openings · seen", response.body
    assert_select "form[action=?]", calendar_happening_path(role), false, "nothing to put on a calendar"
    assert_select "form[action=?]", task_happening_path(role)

    post task_happening_path(role)

    task = users(:one).tasks.find_by!(title: "Look into volunteering: Weekend dog walker")
    assert_equal [ "people" ], task.sections.map(&:slug)
  end

  test "an opening the causes brief matched shows on the People hub as Give time" do
    users(:one).update!(causes_brief: "Animals.")
    role = @source.happenings.create!(uid: "walk", kind: "opening", title: "Weekend dog walker", location: "Tulsa SPCA")
    HappeningMatch.create!(happening: role, target: "causes", reason: "animals, on a weekend")
    unmatched = @source.happenings.create!(uid: "other", kind: "opening", title: "Phone banking")

    get section_path("people")

    assert_response :success
    assert_select "[data-give-time]"
    assert_match "Weekend dog walker", response.body
    assert_no_match "Phone banking", response.body
    assert_match CGI.escapeHTML(happenings_path(kind: "opening")), response.body

    role.matches.each(&:reject!)
    get section_path("people")
    assert_select "[data-give-time]", false, "nothing matched is zero pixels, not an empty card"
    assert unmatched
  end

  test "an opening the source stopped listing is withdrawn and pruned like an event" do
    role = @source.happenings.create!(uid: "walk", kind: "opening", title: "Weekend dog walker", last_seen_at: 2.days.ago)
    Web::Fetch.resolver = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new
    stub_request(:get, @source.url).to_return(
      body: %(<script type="application/ld+json">{"@type":"JobPosting","title":"Cat cuddler","employmentType":"VOLUNTEER"}</script>),
      headers: { "Content-Type" => "text/html" })

    result = Listings::Refresh.call(@source)

    assert_equal 1, result.added
    assert_equal 1, result.withdrawn
    assert role.reload.withdrawn?
  ensure
    Web::Fetch.resolver = Resolv
  end
end
