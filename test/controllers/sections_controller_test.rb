require "test_helper"

class SectionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "shows visible items tagged with the section or its subsections" do
    mine = users(:one).tasks.create!(title: "Review budget")
    mine.sections << sections(:budget)
    other = users(:two).tasks.create!(title: "Bob money thing")
    other.sections << sections(:money)

    get section_path("money")
    assert_response :success
    assert_match "Review budget", response.body
    assert_no_match "Bob money thing", response.body
  end

  test "404s on an unknown section" do
    get section_path("nonsense")
    assert_response :not_found
  end

  test "shows the section's tools, including subsection tools on the parent page" do
    get section_path("rights")
    assert_response :success
    assert_match "Draft a dispute letter", response.body

    get section_path("disputes")
    assert_match "Draft a dispute letter", response.body
  end

  test "a section with no tools shows none" do
    get section_path("health")
    assert_response :success
    assert_no_match "Draft a dispute letter", response.body
  end

  test "education leads with the learn-something tool" do
    get section_path("education")
    assert_response :success
    assert_match "Learn something", response.body
  end

  test "the empty state offers capture pre-tagged with the section" do
    get section_path("health")
    assert_response :success
    assert_match "Nothing in Health yet", response.body
    assert_match new_task_path(section_ids: [ sections(:health).id ]), response.body
  end

  test "the Health page leads with the care radar, all kinds untracked for a fresh user" do
    get section_path("health")
    assert_response :success
    assert_match "Routine care", response.body
    assert_match "Not tracked", response.body
    assert_match "Insurance &amp; coverage", response.body
    assert_match "Upload a plan document", response.body
    assert_match new_tool_run_path("find_care", inputs: { specialty: "dentist" }), response.body
  end

  test "the care radar shows booked and due states from the user's own events" do
    booked = users(:one).events.create!(title: "Dentist", starts_at: 3.weeks.from_now, all_day: true)
    booked.sections << sections(:health)
    old_eyes = users(:one).events.create!(title: "Eye exam", starts_at: 30.months.ago, all_day: true)
    old_eyes.sections << sections(:health)

    get section_path("health")
    assert_response :success
    assert_match "Booked", response.body
    assert_match event_path(booked), response.body
    assert_match "Due", response.body
    assert_match "Log a past visit", response.body, "the untracked checkup kind offers past-visit capture"
  end

  test "the coverage card lists plan-shaped documents and offers the insurance tools prefilled" do
    document = users(:one).documents.create!(title: "Acme PPO Summary of Benefits")

    get section_path("health")
    assert_response :success
    assert_match "Acme PPO Summary of Benefits", response.body
    assert_match new_tool_run_path("insurance_explainer", inputs: { document_id: document.id }), response.body
    assert_no_match "Compare plans →", response.body, "comparison needs two plan documents"
  end

  test "other section pages get no care radar" do
    get section_path("money")
    assert_response :success
    assert_no_match "Routine care", response.body
  end

  test "the Hobbies page asks what you do for fun and suggests hobbies" do
    get section_path("hobbies")
    assert_response :success
    assert_match "What do you do for fun?", response.body
    assert_match "Woodworking", response.body
    assert_match "Start a hobby", response.body
  end

  test "with lenses the capture card shrinks and taken suggestions disappear" do
    Hobbies::Lens.find_or_create!("Woodworking")

    get section_path("hobbies")
    assert_response :success
    assert_match "Add another hobby", response.body
    assert_match "Hobbies · Woodworking", response.body, "the lens shows as a header chip"
    assert_no_match "hobbies?name=Woodworking", response.body
  end

  test "a hobby lens page gets the parent's tools and a remove affordance" do
    lens = Hobbies::Lens.find_or_create!("Guitar")

    get section_path(lens.slug)
    assert_response :success
    assert_match "Start a hobby", response.body
    assert_match "Find your people", response.body
    assert_match "Remove this hobby", response.body
  end

  test "seeded subsections get no remove affordance" do
    get section_path("budget")
    assert_response :success
    assert_no_match "Remove this hobby", response.body
  end

  test "the Attend zone shows pending suggestions tagged with the section, on parent and lens pages" do
    lens = Hobbies::Lens.find_or_create!("Guitar")
    suggestion = users(:one).suggestions.create!(
      watcher_slug: "neglected_hobby", fingerprint: "neglected_hobby/lens:#{lens.id}",
      title: "It's been a while since anything Guitar",
      action: { "event" => { "title" => "Guitar session", "starts_at" => Date.tomorrow.iso8601 } }
    )
    suggestion.sections = [ sections(:hobbies), lens ]

    get section_path("hobbies")
    assert_match "been a while since anything Guitar", response.body

    get section_path(lens.slug)
    assert_match "been a while since anything Guitar", response.body

    get section_path("health")
    assert_no_match "been a while", response.body

    suggestion.dismiss!
    get section_path("hobbies")
    assert_no_match "been a while", response.body
  end
end
