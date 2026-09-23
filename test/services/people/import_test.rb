require "test_helper"

class People::ImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @user = users(:one) }

  def import(fixture)
    People::Import.new(user: @user, file: file_fixture(fixture).open).call
  end

  test "imports a vCard file with names, phones, emails, addresses, birthdays" do
    result = assert_difference("@user.people.count", 3) { import("contacts.vcf") }

    assert_equal 3, result.imported
    assert_equal 0, result.skipped
    assert_nil result.error

    maria = @user.people.find_by!(name: "Maria Rivera")
    assert_equal "+15550102000", maria.phone
    assert_equal "maria@example.com", maria.email
    assert_equal "123 Main St, Springfield, IL, 62704, USA", maria.address
    assert_equal Date.new(1975, 4, 5), maria.birthday
    assert_includes maria.notes, "Mom's cardiologist. Prefers mornings, weekdays only."
    assert_includes maria.notes, "Company: St. Mary's Hospital, Cardiology"
    assert_includes maria.notes, "Work phone: +1 (555) 010-2001"
    assert_includes maria.notes, "Work email: m.rivera@stmarys.example.com"
  end

  test "imports a LinkedIn connections export, preamble and all" do
    result = assert_difference("@user.people.count", 2) { import("linkedin_connections.csv") }

    assert_equal 2, result.imported
    assert_nil result.error

    dana = @user.people.find_by!(name: "Dana Nguyen")
    assert_equal "dana@example.com", dana.email
    assert_includes dana.notes, "Position: Operations Manager"
    assert_includes dana.notes, "Connected on LinkedIn: 12 Mar 2024"
    assert_includes dana.notes, "LinkedIn: https://www.linkedin.com/in/dana-nguyen"
    assert_includes dana.notes, "Company: Acme Logistics"

    luis = @user.people.find_by!(name: "Luis Ortega")
    assert_nil luis.email, "LinkedIn hides most emails; absence must not invent one"
  end

  test "handles vCard 2.1 quoted-printable and compact birthdays" do
    import("contacts.vcf")

    linh = @user.people.find_by!(name: "Linh Nguyen")
    assert_equal "+15550103000", linh.phone
    assert_equal Date.new(1988, 11, 20), linh.birthday
    assert_includes linh.notes, "Met at the café"
  end

  test "unfolds folded vCard lines" do
    import("contacts.vcf")

    person = @user.people.find_by!(name: "Folded Note Person")
    assert_includes person.notes, "This note is folded across two lines per RFC."
  end

  test "tags imported people with the People section and skips auto-sort" do
    assert_no_enqueued_jobs(only: CategorizePersonJob) { import("contacts.vcf") }

    assert_equal [ sections(:people) ], @user.people.find_by!(name: "Maria Rivera").sections
  end

  test "imports a Google Contacts CSV" do
    result = import("google_contacts.csv")
    assert_equal 2, result.imported

    rosa = @user.people.find_by!(name: "Rosa Diaz")
    assert_equal "+15550201000", rosa.phone
    assert_equal "rosa@example.com", rosa.email
    assert_equal "456 Oak Ave, Portland, OR 97201", rosa.address
    assert_equal Date.new(1990, 2, 14), rosa.birthday
    assert_includes rosa.notes, "Loves hiking"
    assert_includes rosa.notes, "Company: Acme Corp"
    assert_includes rosa.notes, "Work phone: +1 555 020 1001"
    assert_includes rosa.notes, "Mother: Elena Diaz"

    sam = @user.people.find_by!(name: "Sam Lee")
    assert_equal "sam@example.com", sam.email
    assert_includes sam.notes, "email: sam.work@example.com"
  end

  test "imports an Outlook CSV" do
    result = import("outlook_contacts.csv")
    assert_equal 1, result.imported

    priya = @user.people.find_by!(name: "Priya Patel")
    assert_equal "priya@example.com", priya.email
    assert_equal "+15550301000", priya.phone
    assert_equal "12 Elm St, Austin, TX, 78701, USA", priya.address
    assert_equal Date.new(1985, 4, 5), priya.birthday
    assert_includes priya.notes, "Old coworker"
    assert_includes priya.notes, "Company: Initech (Engineer)"
    assert_includes priya.notes, "Work phone: +1 555 030 1001"
    assert_includes priya.notes, "Other email: ppatel@initech.example.com"
    assert_includes priya.notes, "Work address: 100 Corporate Dr, Austin, TX, 78702, USA"
  end

  test "imports any CSV with recognizable headers" do
    result = import("generic_contacts.csv")
    assert_equal 1, result.imported

    joe = @user.people.find_by!(name: "Uncle Joe")
    assert_equal "uncle", joe.relationship
    assert_equal "+15550401000", joe.phone
    assert_equal "joe@example.com", joe.email
    assert_equal "9 Pine Rd, Boise, ID", joe.address
    assert_equal Date.new(1960, 6, 1), joe.birthday
    assert_includes joe.notes, "Calls on Sundays"
    assert_includes joe.notes, "Work phone: +1 555 040 1001"
  end

  test "imports Contact Picker JSON from the on-device mobile path" do
    result = assert_difference("@user.people.count", 2) { import("device_contacts.json") }

    assert_equal 2, result.imported
    assert_nil result.error

    nadia = @user.people.find_by!(name: "Nadia Osman")
    assert_equal "+15550301000", nadia.phone
    assert_equal "nadia@example.com", nadia.email
    assert_equal "12 Elm Court, Apt 4, Austin, TX, 78701, USA", nadia.address
    assert_includes nadia.notes, "Other phone: +1 555 030 1001"
    assert_equal [ sections(:people) ], nadia.sections

    assert @user.people.exists?(name: "Omar Haddad")
    assert_not @user.people.exists?(phone: "+1 555 030 2000"), "nameless picker entries are skipped"
  end

  # D-contact-photos: an address book arrives with faces, in the three
  # shapes real exports use.
  test "attaches vCard photos, base64 and data URI alike" do
    import("contacts.vcf")

    maria = @user.people.find_by!(name: "Maria Rivera")
    assert maria.avatar.attached?, "ENCODING=b photo, folded across lines, should ride in"
    assert_equal "image/png", maria.avatar.blob.content_type

    assert @user.people.find_by!(name: "Folded Note Person").avatar.attached?,
      "a vCard 4.0 data: URI photo should ride in too"
  end

  test "a photo that is only a link is left alone — no third-party fetch on import" do
    import("contacts.vcf")

    assert_not @user.people.find_by!(name: "Linh Nguyen").avatar.attached?
  end

  test "attaches the icon the phone's contact picker hands over" do
    import("device_contacts.json")

    nadia = @user.people.find_by!(name: "Nadia Osman")
    assert nadia.avatar.attached?
    assert_equal "image/png", nadia.avatar.blob.content_type
    assert_not @user.people.find_by!(name: "Omar Haddad").avatar.attached?
  end

  test "a corrupt photo costs the contact its face, not the import" do
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:Broken Photo
      PHOTO;ENCODING=b;TYPE=JPEG:not-actually-base64!!
      END:VCARD
    VCF

    result = assert_difference("@user.people.count", 1) do
      People::Import.new(user: @user, content: vcf, filename: "broken.vcf").call
    end

    assert_equal 1, result.imported
    assert_not @user.people.find_by!(name: "Broken Photo").avatar.attached?
  end

  test "skips contacts already in the address book by name" do
    @user.people.create!(name: "Maria Rivera", phone: "keep me")

    result = import("contacts.vcf")
    assert_equal 2, result.imported
    assert_equal 1, result.skipped
    assert_equal "keep me", @user.people.find_by!(name: "Maria Rivera").phone
  end

  test "importing the same file twice is idempotent" do
    import("contacts.vcf")
    result = assert_no_difference("Person.count") { import("contacts.vcf") }

    assert_equal 0, result.imported
    assert_equal 3, result.skipped
  end

  test "rejects files that are not address books" do
    result = assert_no_difference("Person.count") { import("sample.txt") }

    assert_equal 0, result.imported
    assert_match(/doesn't look like an address book/, result.error)
  end
end
