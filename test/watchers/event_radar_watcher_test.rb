require "test_helper"

# The event radar's watcher (D-event-radar §7): matched listings inside a
# place's lead time become ordinary suggestions, soonest first, a handful
# per place, one per series; accepting lands the row through the river's
# own path; retiring follows the world; dismissing teaches the matcher.
class EventRadarWatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @birding = Hobbies::Lens.find_or_create!("Birding")
    @place = @user.places.create!(name: "Tulsa", lead_days: 14)
    @source = @place.listing_sources.create!(url: "https://library.example/cal.ics", title: "Library")
  end

  test "a matched listing inside the lead time earns a date-first nudge whose accept adds it to the calendar" do
    walk = matched(listing("Fall bird walk", at: 3.days.from_now.change(hour: 9), location: "Lakeside Park", distance_mi: 6))
    listing("Council budget meeting", at: 4.days.from_now)

    suggestion = scan.sole

    assert_equal "event_radar/happening:#{walk.id}", suggestion.fingerprint
    assert_equal "#{walk.starts_at.strftime("%a %-d %b")} · Fall bird walk (Birding, 6 mi)", suggestion.title
    assert_match "A guided walk for birders.", suggestion.body
    assert_match "Lakeside Park", suggestion.body
    assert_match "From Library.", suggestion.body
    assert_equal "Add to calendar", suggestion.accept_label
    assert_equal walk.starts_at.to_date.iso8601, suggestion.action["expires_on"]
    assert_equal %w[ birding hobbies ], suggestion.sections.map(&:slug).sort

    event = suggestion.accept!

    assert_equal "Fall bird walk", event.title
    assert_equal %w[ birding hobbies ], event.sections.map(&:slug).sort
    assert_equal event, walk.reload.event
  end

  test "beyond the lead time is the river's, not the nudge's" do
    matched(listing("Far-off festival", at: 30.days.from_now))

    assert_empty scan
  end

  test "at most a handful per place, soonest first, and one per series" do
    7.times { |n| matched(listing("Thing #{n}", uid: "t#{n}", at: (n + 1).days.from_now)) }
    3.times { |n| matched(listing("Tuesday walk", uid: "tue/#{n}", series: "tue", at: (n + 1).days.from_now)) }

    titles = scan.map(&:title)

    assert_equal Watcher::EventRadar::MAX_PER_PLACE, titles.size
    assert_equal 1, titles.count { |title| title.include?("Tuesday walk") }
    assert titles.any? { |title| title.include?("Thing 0") }
    assert titles.none? { |title| title.include?("Thing 6") }
  end

  test "a row the user saved themselves is nudged with no match and no model" do
    @user.household.model_profile.update!(api_key: "")
    listing("Jazz at the Vanguard", at: 2.days.from_now, provenance: "saved")

    suggestion = scan.sole

    assert_match "You saved this yourself.", suggestion.body
    assert_equal [ "hobbies" ], suggestion.sections.map(&:slug)
  end

  test "a volunteer opening is nudged once it is seen, and accepting makes a task" do
    @user.update!(causes_brief: "Animals.")
    role = listing("Weekend dog walkers", kind: "opening", at: nil, location: "Tulsa SPCA", expires_on: 20.days.from_now.to_date)
    HappeningMatch.create!(happening: role, target: "causes", reason: "animals, on a weekend")

    suggestion = scan.sole

    assert_equal "Weekend dog walkers — volunteers wanted (A cause)", suggestion.title
    assert_equal "Make a task", suggestion.accept_label
    assert_equal [ "people" ], suggestion.sections.map(&:slug)
    assert_equal role.expires_on.iso8601, suggestion.action["expires_on"]

    task = suggestion.accept!

    assert_equal "Look into volunteering: Weekend dog walkers", task.title
    assert_equal [ "people" ], task.sections.map(&:slug)
  end

  test "a place with alerts off keeps its river and loses its nudges" do
    @place.update!(alerts: false)
    matched(listing("Fall bird walk", at: 3.days.from_now))

    assert_empty scan
  end

  test "a nudge retires when the world resolves it, and never re-proposes" do
    walk = matched(listing("Fall bird walk", at: 3.days.from_now))
    suggestion = scan.sole
    check = Watcher::EventRadar.new(@user)

    assert_not check.resolved?(suggestion)

    walk.add_to_calendar!
    assert check.resolved?(suggestion), "you put it on your calendar yourself"
    walk.update!(event: nil)

    walk.matches.each(&:reject!)
    assert check.resolved?(suggestion), "the match was rejected on the row"
    walk.happening_matches.each(&:restore!)

    walk.hide!
    assert check.resolved?(suggestion)
    walk.unhide!

    walk.update!(withdrawn_at: Time.current)
    assert check.resolved?(suggestion), "the source stopped listing it"

    walk.destroy!
    assert check.resolved?(suggestion), "pruned is nothing left to nudge about"
    assert_empty scan, "the fingerprint stands"
  end

  test "dismissing the nudge rejects the match, so the title comes back as an example" do
    walk = matched(listing("Fall bird walk", at: 3.days.from_now))
    suggestion = scan.sole

    suggestion.dismiss!

    assert suggestion.dismissed?
    assert walk.reload.happening_matches.sole.rejected?
    assert_not walk.matched?
  end

  test "the scan job runs it under the Hobbies dial and retires what resolved" do
    @user.household.model_profile.update!(api_key: "") # no digest call to stub
    walk = matched(listing("Fall bird walk", at: 3.days.from_now))
    AgentScanJob.perform_now(@user, cadence: "weekly")
    suggestion = @user.suggestions.find_by!(watcher_slug: "event_radar")
    assert suggestion.pending?

    walk.add_to_calendar!
    AgentScanJob.perform_now(@user, cadence: "weekly")

    assert suggestion.reload.resolved?
  end

  test "another member's listings are never yours to be nudged about" do
    theirs = users(:two).places.create!(name: "Austin").listing_sources.create!(url: "https://x.example/cal.ics")
    row = theirs.happenings.create!(uid: "t", title: "Bob's thing", starts_at: 2.days.from_now)
    HappeningMatch.create!(happening: row, target: "household", reason: "theirs")

    assert_empty scan
  end

  private
    def scan
      watcher = Watcher::EventRadar.new(@user)
      watcher.scan
      watcher.proposals
    end

    def listing(title, uid: title.parameterize, series: nil, at:, kind: "event", **attrs)
      @source.happenings.create!(uid: uid, series_uid: series || uid, title: title, starts_at: at, kind: kind, **attrs)
    end

    def matched(row)
      HappeningMatch.create!(happening: row, target: "section:#{@birding.id}", section: @birding, reason: "a guided walk for birders")
      row
    end
end
