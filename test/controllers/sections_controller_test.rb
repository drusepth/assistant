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

  test "seeded subsections browse as compact tiles with signal, not header chips" do
    task = users(:one).tasks.create!(title: "Review budget")
    task.sections << sections(:budget)

    get section_path("money")
    assert_response :success
    assert_match "Browse", response.body
    assert_match section_path("budget"), response.body, "the tile links to the subsection page"
    assert_match "1 open task", response.body
    assert_match "Nothing yet", response.body, "empty subsections say so honestly"

    get section_path("rights")
    assert_response :success
    assert_match "Browse", response.body
    assert_match section_path("disputes"), response.body
  end

  test "a subsection tile leads with the next upcoming event" do
    event = users(:one).events.create!(title: "Lease renewal", starts_at: 5.days.from_now)
    event.sections << sections(:renting)

    get section_path("rights")
    assert_response :success
    assert_match "Lease renewal", response.body
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

  test "education's panel surfaces the two doors instead of the tool cards it hides (D37)" do
    get section_path("education")
    assert_response :success
    assert_match "The school shelf", response.body
    assert_match "Learn anything", response.body
    assert_no_match "tools/learn_something/run", response.body, "the panel hides the card it surfaces with better context"
  end

  test "the empty state offers capture pre-tagged with the section" do
    get section_path("health")
    assert_response :success
    assert_match "Nothing in Health yet", response.body
    # Inline, with the section riding along as a pre-tag…
    assert_select "form[action=?] input[type=hidden][name=?][value=?]",
      tasks_path, "task[section_ids][]", sections(:health).id.to_s
    # …and the way out to the standalone page carries it too.
    assert_select "a[href=?]", new_task_path(section_ids: [ sections(:health).id ], return_to: section_path("health")),
      text: "Full form"
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

  test "the haircut tile tracks like any kind but offers no medical next-click" do
    users(:one).events.create!(title: "Haircut", starts_at: 5.months.ago, all_day: true)
      .sections << sections(:health)

    get section_path("health")
    assert_response :success
    assert_match "Haircut", response.body
    assert_match "Last haircut", response.body
    assert_no_match(
      Regexp.new(Regexp.escape(new_tool_run_path("find_care", inputs: { specialty: "barber or hair stylist" }))),
      response.body,
      "find-care finds doctors, not barbers"
    )
  end

  test "the coverage card lists plan-shaped documents and offers the insurance tools prefilled" do
    document = users(:one).documents.create!(title: "Acme PPO Summary of Benefits")

    get section_path("health")
    assert_response :success
    assert_match "Acme PPO Summary of Benefits", response.body
    assert_match new_tool_run_path("insurance_explainer", inputs: { document_id: document.id }), response.body
    assert_no_match "Compare plans →", response.body, "comparison needs two plan documents"
  end

  test "the Mind card offers check-in, practice, and find-a-therapist with the honesty line" do
    get section_path("health")
    assert_response :success
    assert_match "Mind", response.body
    assert_match new_tool_run_path("check_in"), response.body
    assert_match new_tool_run_path("start_a_practice"), response.body
    assert_match "not therapy", response.body
    assert_no_match "pick it back up", response.body, "no continuity line before a first check-in"
  end

  test "a finished check-in gets a pick-it-back-up link" do
    run = users(:one).tool_runs.create!(tool_slug: "check_in", inputs: {}, status: :done)

    get section_path("health")
    assert_response :success
    assert_match "pick it back up", response.body
    assert_match tool_run_path(run), response.body
  end

  test "other section pages get no care radar" do
    get section_path("money")
    assert_response :success
    assert_no_match "Routine care", response.body
  end

  test "the Career panel leads with the signal capture, the timeline, and the scout's feeds" do
    Career::WinLog.log!(user: users(:one), text: "Caught the inventory error before the audit")
    Career::CompChange.log!(user: users(:one), summary: "Raise: $19 → $21/hr", on: 14.months.ago.to_date)
    users(:one).job_feeds.create!(url: "https://boards.greenhouse.io/acme", label: "Acme board")

    get section_path("career")

    assert_response :success
    assert_match "Your work, on the record", response.body
    assert_match "Caught the inventory error before the audit", response.body
    assert_match "14 months ago", response.body
    assert_match "Acme board", response.body
    assert_select "form[action=?]", career_win_path
    assert_select "form[action=?]", job_feeds_path
  end

  test "the Act zone hides tools the lead panels already carry" do
    get section_path("health")
    assert_response :success
    assert_no_match "A plan for finding the right in-network provider", response.body,
      "find-care's card is gone — the radar's prefilled links carry it"
    assert_match "Prep for a doctor visit", response.body, "un-paneled tools keep their cards"
  end

  test "household care shows exactly what other members share (kids are users too)" do
    kid = users(:two)
    shared = kid.events.create!(title: "Dentist", starts_at: 2.weeks.from_now, all_day: true)
    shared.sections << sections(:health)
    AccessGrant.create!(grantor: kid, grantee: users(:one), subject: shared)
    hidden = kid.events.create!(title: "Eye exam", starts_at: 3.weeks.from_now, all_day: true)
    hidden.sections << sections(:health)

    get section_path("health")
    assert_response :success
    assert_match "Household care", response.body
    assert_match "Dental — booked", response.body
    assert_no_match "Vision —", response.body, "the unshared eye exam stays invisible"
  end

  test "a pet's vaccines needing attention join the household care strip" do
    rex = create_pet(user: users(:one))
    rex.pet_vaccinations.create!(user: users(:one), vaccine_key: "rabies", given_on: 3.years.ago.to_date,
      due_on: 10.days.from_now.to_date)

    get section_path("health")
    assert_match "Household care", response.body
    assert_match "Rabies — due soon #{10.days.from_now.strftime("%b %-d")}", response.body
  end

  test "no shared health events means no household care card" do
    get section_path("health")
    assert_no_match "Household care", response.body
  end

  test "a booked radar tile offers visit prep prefilled" do
    booked = users(:one).events.create!(title: "Annual physical", starts_at: 3.weeks.from_now, all_day: true)
    booked.sections << sections(:health)

    get section_path("health")
    assert_match "Prep for this visit", response.body
    assert_match new_tool_run_path("doctor_visit_prep", inputs: { reason: "Annual physical" }), response.body
  end

  test "the medications card lists meds and takes new ones" do
    med = users(:one).notes.create!(kind: Note::MEDICATION, title: "Lisinopril 10mg", body: "one every morning")
    med.sections << sections(:health)

    get section_path("health")
    assert_response :success
    assert_match "Medications", response.body
    assert_match "Lisinopril 10mg", response.body
    assert_match medications_path, response.body
  end

  test "the Hobbies page asks what you do for fun and suggests hobbies" do
    get section_path("hobbies")
    assert_response :success
    assert_match "What do you do for fun?", response.body
    assert_match "Woodworking", response.body
    assert_match "Start a hobby", response.body
  end

  test "with lenses the page shows a hobby card grid and capture shrinks to the add tile" do
    lens = Hobbies::Lens.find_or_create!("Woodworking")

    get section_path("hobbies")
    assert_response :success
    assert_match "Your hobbies", response.body
    assert_match section_path(lens.slug), response.body, "the lens card links to the lens page"
    assert_no_match "Hobbies · Woodworking", response.body, "cards drop the parent prefix"
    assert_no_match "What do you do for fun?", response.body
    assert_match "Add another hobby", response.body
    assert_no_match "hobbies?name=Woodworking", response.body
  end

  test "hobby cards carry engagement signal: next event and in-flight counts" do
    lens = Hobbies::Lens.find_or_create!("Guitar")
    event = users(:one).events.create!(title: "Open mic night", starts_at: 3.days.from_now)
    event.sections << lens
    task = users(:one).tasks.create!(title: "Restring the acoustic")
    task.sections << lens

    get section_path("hobbies")
    assert_response :success
    # One short signal beside the name (D-hobby-feeds): the date, with the
    # event's own title on hover. The full picture is on the lens page.
    assert_select "[data-hobby-card=?] [title=?]", lens.slug, "Open mic night"
    assert_match event.starts_at.strftime("%b %-d"), response.body
  end

  # A hobby with nothing in it is a link in the Explore card rather than a
  # card of its own (D-hobby-feeds); the rule is exercised properly in
  # hobbies_reader_panel_test.
  test "a quiet hobby is somewhere to go, not a card" do
    lens = Hobbies::Lens.find_or_create!("Sandboarding")

    get section_path("hobbies")
    assert_response :success
    assert_select "[data-hobby-explore] a[href=?]", section_path(lens.slug), text: lens.name
    assert_select "[data-hobby-card=?]", lens.slug, false
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

  test "the People page is the circle's dashboard, not the roster (D-people-dashboard)" do
    users(:one).people.create!(name: "Circle Sam", keep_in_touch: true, last_contacted_on: 2.weeks.ago.to_date)
    rolodex = users(:one).people.create!(name: "Rolodex Rex")
    rolodex.sections << sections(:people)

    get section_path("people")
    assert_response :success
    assert_match "Your circle", response.body
    assert_match "Circle Sam", response.body
    assert_match "Last contact", response.body
    assert_match "in your Address Book", response.body
    assert_select "a", { text: "Rolodex Rex", count: 0 },
      "unflagged people belong to the Address Book"
  end

  # D-person-picker: the address book is searched, never listed — a real
  # import made the old <select> unusable — and the lead capture steps
  # aside once the circle card can do the same job.
  test "the People page leads with circle capture while the circle is empty, without listing the address book" do
    users(:one).people.create!(name: "Pickable Pat")

    get section_path("people")
    assert_match "Who do you want to stay close to?", response.body
    assert_select "form[action=?] input[role=combobox][name=name]", people_circle_path
    assert_no_match "Pickable Pat", response.body, "the roster is found by typing, not rendered into the page"
    assert_select "select[name=person_id]", false

    users(:one).people.create!(name: "Flagged", keep_in_touch: true)
    get section_path("people")
    assert_no_match "Who do you want to stay close to?", response.body
    # A non-empty circle is added to from its own card.
    assert_select "details form[action=?] input[role=combobox]", people_circle_path
  end

  test "Coming up lists circle birthdays but not the rolodex's" do
    users(:one).people.create!(name: "Birthday Kid", keep_in_touch: true, birthday: 10.days.from_now.to_date - 30.years)
    users(:one).people.create!(name: "Distant Cousin", birthday: 10.days.from_now.to_date - 40.years)

    get section_path("people")
    assert_match "Coming up", response.body
    assert_match "Birthday Kid", response.body
    assert_select "a", { text: "Distant Cousin", count: 0 },
      "rolodex birthdays stay off the dashboard"
  end

  test "the People page offers group capture and lists existing groups" do
    People::Group.find_or_create!("D&D table")

    get section_path("people")
    assert_match "Start a group", response.body
    assert_match "D&amp;D table", response.body
  end

  # D-people-circles: groups and the circle are one grid of one card, so a
  # group carries faces, a count and a next thing — not a bare chip.
  test "the circles grid draws every collection of people as a card" do
    group = People::Group.find_or_create!("Book club")
    users(:one).people.create!(name: "Rosa").sections << group
    users(:one).people.create!(name: "Circle Sam", keep_in_touch: true)

    get section_path("people")
    assert_response :success

    assert_match "Your people", response.body
    assert_match "Only you", response.body, "the circle card says it isn't shared with the household"
    assert_match "Book club", response.body
    assert_match "1 person · nothing planned yet", response.body
    assert_select "a[href=?]", people_path(circle: "1"), { count: 1 },
      "the circle card opens the full circle"
    assert_select "a[href=?]", section_path(group.slug)
    assert_no_match "People · Book club", response.body,
      "a card is inside People already — the qualified name was noise"
  end

  test "every card can add someone, and a group card can plan something" do
    People::Group.find_or_create!("Book club")

    get section_path("people")
    assert_select "form[action=?]", people_memberships_path
    assert_select "form[action=?]", people_circle_path
    assert_match "Plan something", response.body
  end

  test "a group page leads with its members and the way to add one" do
    group = People::Group.find_or_create!("Book club")
    users(:one).people.create!(name: "Rosa", relationship: "neighbor").sections << group

    get section_path(group.slug)
    assert_response :success
    assert_match "Members", response.body
    assert_match "Rosa", response.body
    assert_select "form[action=?]", people_memberships_path
    assert_select "form[action=?]", people_membership_path(section_id: group.id, person_id: Person.find_by(name: "Rosa").id)
  end

  test "other sections keep their filtered person lists" do
    doctor = users(:one).people.create!(name: "Dr. Chen")
    doctor.sections << sections(:health)

    get section_path("health")
    assert_match "Dr. Chen", response.body
  end
end
