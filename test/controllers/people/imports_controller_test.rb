require "test_helper"

class People::ImportsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "shows the import form" do
    get new_people_import_path
    assert_response :success
    assert_match "Import contacts", response.body
  end

  test "imports an uploaded vCard and reports the count" do
    assert_difference("users(:one).people.count", 3) do
      post people_import_path, params: { file: fixture_file_upload("contacts.vcf", "text/vcard") }
    end

    assert_redirected_to people_path
    assert_equal "Imported 3 contacts.", flash[:notice]
  end

  test "reports skipped duplicates" do
    users(:one).people.create!(name: "Maria Rivera")

    post people_import_path, params: { file: fixture_file_upload("contacts.vcf", "text/vcard") }
    assert_equal "Imported 2 contacts. Skipped 1 contact already in your address book.", flash[:notice]
  end

  test "imports contacts picked from the device address book" do
    contacts = [
      { name: [ "Device Dana" ], tel: [ "+1 555 050 1000" ], email: [ "dana@example.com" ], address: [] }
    ].to_json

    assert_difference("users(:one).people.count", 1) do
      post people_import_path, params: { contacts: contacts }
    end

    assert_redirected_to people_path
    assert_equal "Imported 1 contact.", flash[:notice]
    assert_equal "+15550501000", users(:one).people.find_by!(name: "Device Dana").phone
  end

  test "rejects an unsupported file" do
    assert_no_difference("Person.count") do
      post people_import_path, params: { file: fixture_file_upload("sample.txt", "text/plain") }
    end

    assert_redirected_to new_people_import_path
    assert_match(/doesn't look like an address book/, flash[:alert])
  end

  test "requires a file" do
    post people_import_path
    assert_redirected_to new_people_import_path
    assert_equal "Choose a file to import.", flash[:alert]
  end

  test "imported people belong to the signed-in user, not the household" do
    post people_import_path, params: { file: fixture_file_upload("generic_contacts.csv", "text/csv") }

    person = Person.find_by!(name: "Uncle Joe")
    assert_equal users(:one), person.user
  end
end
