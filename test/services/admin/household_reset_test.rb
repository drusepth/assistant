require "test_helper"

class Admin::HouseholdResetTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @bob = users(:two)
    @household = households(:smith)
    @outsider = users(:outsider)
  end

  test "takes the household, its members, and everything they own" do
    @alice.tasks.create!(title: "Buy milk")
    @alice.events.create!(title: "Dentist", starts_at: 1.week.from_now)
    @bob.notes.create!(body: "Dummy data")
    @bob.people.create!(name: "Test Person")

    assert_difference -> { User.count } => -2, -> { Household.count } => -1,
                      -> { Task.count } => -1, -> { Event.count } => -1,
                      -> { Note.count } => -1, -> { Person.count } => -1 do
      Admin::HouseholdReset.call(@household)
    end
  end

  test "reports what it deleted" do
    @alice.tasks.create!(title: "Buy milk")
    @alice.goals.create!(title: "Get a job")
    @bob.notes.create!(body: "Dummy data")

    summary = Admin::HouseholdReset.call(@household)

    assert_equal 2, summary[:members]
    assert_equal 3, summary[:items]
  end

  test "preview counts the same things without deleting them" do
    @alice.tasks.create!(title: "Buy milk")

    assert_no_difference -> { Task.count } do
      assert_equal({ members: 2, items: 1 }, Admin::HouseholdReset.preview(@household))
    end
  end

  test "leaves other households untouched" do
    @outsider.tasks.create!(title: "Not mine to delete")

    Admin::HouseholdReset.call(@household)

    assert User.exists?(@outsider.id)
    assert_equal 1, @outsider.reload.tasks.count
  end

  test "clears the error log for the household's members" do
    AppError.record(StandardError.new("boom"), source: "TestJob", user: @alice)

    assert_difference -> { AppError.count }, -1 do
      Admin::HouseholdReset.call(@household)
    end
  end

  test "takes user-created lenses with it once the last household is gone" do
    Sections::Lens.find_or_create!("hobbies", "Kayaking", fallback_slug: "hobby")
    households(:jones).destroy!

    Admin::HouseholdReset.call(@household)

    assert_empty Section.custom
    assert Section.exists?(slug: "hobbies"), "the seeded taxonomy survives"
  end

  test "keeps lenses while another household is still using the instance" do
    Sections::Lens.find_or_create!("hobbies", "Kayaking", fallback_slug: "hobby")

    Admin::HouseholdReset.call(@household)

    assert Section.custom.exists?(name: "Kayaking")
  end

  test "sharing grants between members go with them" do
    task = @alice.tasks.create!(title: "Shared errand")
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: task)

    assert_difference -> { AccessGrant.count }, -1 do
      Admin::HouseholdReset.call(@household)
    end
  end

  # D-purge-by-diff. This used to be a hand-written list of model names, and
  # it had already gone stale twice — recipe images and every avatar survived
  # a reset on a multi-household box, because nobody remembered to add them.
  # Attaching one of *everything* is the point: a kind this test forgets is
  # now still purged, because the mechanism never learned any names.
  test "purges every kind of attached file rather than leaving them for a job" do
    document = @alice.documents.create!(title: "Lease")
    document.file.attach(io: StringIO.new("dummy"), filename: "lease.txt", content_type: "text/plain")
    photo = @alice.photos.new
    photo.image.attach(io: StringIO.new("dummy"), filename: "snap.jpg", content_type: "image/jpeg")
    photo.save!
    recipe = @alice.recipes.create!(title: "Soup")
    recipe.image.attach(io: StringIO.new("dummy"), filename: "soup.jpg", content_type: "image/jpeg")
    person = @alice.people.create!(name: "Dr Chen")
    person.avatar.attach(io: StringIO.new("dummy"), filename: "chen.png", content_type: "image/png")
    pet = create_pet(user: @alice)
    pet.avatar.attach(io: StringIO.new("dummy"), filename: "rex.png", content_type: "image/png")
    @alice.avatar.attach(io: StringIO.new("dummy"), filename: "me.png", content_type: "image/png")
    @alice.export_archive.attach(io: StringIO.new("dummy"), filename: "export.zip", content_type: "application/zip")
    @household.banner.attach(io: StringIO.new("dummy"), filename: "home.jpg", content_type: "image/jpeg")

    blobs = {
      "document" => document.file.blob, "photo" => photo.image.blob,
      "recipe image" => recipe.image.blob, "contact avatar" => person.avatar.blob,
      "pet avatar" => pet.avatar.blob, "member avatar" => @alice.avatar.blob,
      "export archive" => @alice.export_archive.blob, "household banner" => @household.banner.blob
    }

    Admin::HouseholdReset.call(@household)

    blobs.each do |kind, blob|
      assert_not ActiveStorage::Blob.exists?(blob.id), "the #{kind} blob outlived the reset"
      assert_not blob.service.exist?(blob.key), "the #{kind} bytes were left on disk"
    end
  end

  # The two things the old unattached sweep could not do safely, which is why
  # it has to stay gated behind "no households left" and this doesn't.
  test "another household's files, attached or mid-upload, survive the reset" do
    theirs = @outsider.documents.create!(title: "Not mine")
    theirs.file.attach(io: StringIO.new("dummy"), filename: "theirs.txt", content_type: "text/plain")
    attached = theirs.file.blob
    # A direct upload sitting unattached while somebody fills in the form.
    in_flight = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("dummy"), filename: "wip.png", content_type: "image/png")

    Admin::HouseholdReset.call(@household)

    assert ActiveStorage::Blob.exists?(attached.id)
    assert attached.service.exist?(attached.key)
    assert ActiveStorage::Blob.exists?(in_flight.id), "an upload in flight elsewhere on the box is not ours to sweep"
  end

  # The reset is the one place that destroys a household whole, so it walks
  # every cascade at once: polymorphic taggings, the goal/task nullify, album
  # covers, run items, cross-member grants. A missing `dependent:` shows up
  # here as a foreign-key violation and nowhere else.
  test "one of everything comes apart cleanly" do
    goal = @alice.goals.create!(title: "Get a job")
    task = @alice.tasks.create!(title: "Apply", goal: goal)
    task.sections << sections(:career)
    @alice.events.create!(title: "Interview", starts_at: 2.days.from_now, goal: goal)
    document = @alice.documents.create!(title: "Resume")
    document.file.attach(io: StringIO.new("dummy"), filename: "resume.txt", content_type: "text/plain")
    person = @alice.people.create!(name: "Recruiter")
    photo = @alice.photos.new
    photo.image.attach(io: StringIO.new("dummy"), filename: "snap.jpg", content_type: "image/jpeg")
    photo.save!
    photo.photo_people.create!(person: person)
    album = @alice.albums.create!(title: "Trip", cover_photo: photo)
    album.album_photos.create!(photo: photo)
    run = @alice.tool_runs.create!(tool_slug: "task_chat", subject: task)
    run.tool_run_items.create!(item: task)
    run.tool_run_messages.create!(role: "user", content: "hello")
    @alice.suggestions.create!(title: "Try this", watcher_slug: "test", fingerprint: "test-1")
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: sections(:career))

    assert_nothing_raised { Admin::HouseholdReset.call(@household) }

    assert_empty Household.where(id: @household.id)
    [ Task, Event, Goal, Document, Person, Photo, Album, AlbumPhoto, PhotoPerson,
      ToolRun, ToolRunItem, ToolRunMessage, Suggestion, AccessGrant, SectionTagging,
      UserSection, Session ].each do |model|
      assert_equal 0, model.count, "#{model.name} rows outlived the reset"
    end
  end

  test "the confirmation word is exact" do
    assert Admin::HouseholdReset.confirmed?("RESET")
    assert Admin::HouseholdReset.confirmed?("  RESET ")
    assert_not Admin::HouseholdReset.confirmed?("reset")
    assert_not Admin::HouseholdReset.confirmed?("")
    assert_not Admin::HouseholdReset.confirmed?(nil)
  end
  test "mirrored mail goes with the household, even when nothing cascades to it" do
    household = households(:smith)
    account = users(:one).linked_accounts.create!(
      provider: "email", label: "Work",
      credentials: { host: "imap.example.com", username: "one@work.example", password: "pw" })
    folder = EmailFolder.create!(user_id: users(:one).id, linked_account_id: account.id,
      name: "INBOX", role: "inbox")
    message = EmailMessage.create!(user_id: users(:one).id, linked_account_id: account.id,
      email_folder: folder, uid: 1, message_id: "reset@x", thread_key: "reset@x", direction: "inbound")
    EmailTombstone.create!(linked_account_id: account.id, message_id: "removed@x")
    EmailMessageItem.create!(email_message: message, item_type: "Task", item_id: 1)
    # The mirror has no foreign keys into the primary database
    # (D-mirror-database), so simulate the link vanishing without its
    # destroy callback running — the case the orphan sweep exists for.
    LinkedAccount.where(id: account.id).delete_all

    Admin::HouseholdReset.call(household)

    assert_equal 0, EmailMessage.count
    assert_equal 0, EmailFolder.count
    assert_equal 0, EmailTombstone.count
    assert_equal 0, EmailMessageItem.count
  end
end
