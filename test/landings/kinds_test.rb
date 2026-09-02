require "test_helper"

# Each kind's round trip: a model-shaped answer validates to the expected
# attributes, the write produces the expected row, and the duplicate check
# finds what it should.
class Landing::KindsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @context = Landing::Context.new(user: @user)
    @health = sections(:health)
  end

  test "event: a dated visit lands as an all-day event, a stated time makes it timed" do
    landing = Landing::Event.new(@context)
    attrs = landing.validate("title" => "Rex — vaccinations", "on" => "2026-08-12", "time" => "9:30",
      "location" => "Animal Hospital", "description" => "Rabies booster")

    event = landing.land!(attrs, sections: [ @health ])
    assert_equal "Rex — vaccinations", event.title
    assert_equal Time.zone.local(2026, 8, 12, 9, 30), event.starts_at
    assert_not event.all_day?
    assert_equal "Animal Hospital", event.location
    assert_equal [ @health ], event.sections.to_a

    all_day = landing.land!(landing.validate("title" => "Lease ends", "on" => "2027-01-31"), sections: [])
    assert all_day.all_day?
    assert_equal event, landing.duplicate_of("title" => "rex — vaccinations", "on" => "2026-08-12")
    assert_nil landing.duplicate_of("title" => "Rex — vaccinations", "on" => "2026-08-13")
  end

  test "task: lands in Today when due today or earlier, Later otherwise" do
    landing = Landing::Task.new(@context)
    overdue = landing.land!(landing.validate("title" => "Return the form", "due_on" => Date.yesterday.iso8601), sections: [])
    later = landing.land!(landing.validate("title" => "Book a follow-up", "due_on" => 2.weeks.from_now.to_date.iso8601), sections: [])
    undated = landing.land!(landing.validate("title" => "Read the leaflet"), sections: [])

    assert overdue.today?
    assert later.later?
    assert undated.later?
    assert_equal later, landing.duplicate_of("title" => "book a follow-up")
  end

  test "note: body falls back to the title, and a plain note with the same title is a duplicate" do
    landing = Landing::Note.new(@context)
    note = landing.land!(landing.validate("title" => "Policy number", "body" => "ABC-123"), sections: [ @health ])
    assert_equal "ABC-123", note.body
    assert note.plain?

    bare = landing.land!(landing.validate("title" => "Just a title"), sections: [])
    assert_equal "Just a title", bare.body
    assert_equal note, landing.duplicate_of("title" => "policy number")
  end

  test "person: lands in the Address Book with what the document gave, and matches an existing name" do
    landing = Landing::Person.new(@context)
    attrs = landing.validate("name" => "Dr. Alvarez", "relationship" => "Vet", "phone" => "555-0100", "email" => "", "ignored" => "x")
    assert_equal({ "name" => "Dr. Alvarez", "relationship" => "Vet", "phone" => "555-0100" }, attrs)

    person = landing.land!(attrs, sections: [])
    assert_equal "Vet", person.relationship
    assert_equal person, landing.duplicate_of("name" => "dr. alvarez")
    assert_equal "person:dr-alvarez", landing.fingerprint(attrs)
  end

  test "coerce keeps every error for the form path, while validate drops what it can and sinks the rest" do
    landing = Landing::Event.new(@context)

    draft = landing.coerce({ "title" => "", "on" => "12 Aug", "time" => "25:00" })
    assert_equal [ "Title is required", "On isn't a date (use YYYY-MM-DD)", "Time isn't a time (use HH:MM)" ],
      draft.errors.full_messages

    assert_nil landing.validate("title" => "Visit", "on" => "12 Aug"), "a required field that doesn't parse sinks the entry"
    assert_equal({ "title" => "Visit", "on" => "2026-08-12" }, landing.validate("title" => "Visit", "on" => "2026-08-12", "time" => "noon"))
  end

  test "references resolve only through what the user can see" do
    rex = create_pet(user: @user)
    other = create_pet(user: users(:two), name: "Luna")

    assert_equal rex, @context.resolve(:pet, rex.section.slug)
    assert_nil @context.resolve(:pet, other.section.slug), "another member's unshared pet is not in the closed set"
    assert_equal [ [ "Rex, dog", rex.section.slug ] ], @context.ref_options(:pet)
  end
end
