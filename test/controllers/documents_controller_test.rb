require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "uploads a document with a file" do
    assert_difference("Document.count") do
      post documents_path, params: {
        document: {
          title: "Lease",
          file: fixture_file_upload("sample.txt", "text/plain"),
          section_ids: [ sections(:rights).id ]
        }
      }
    end
    assert Document.last.file.attached?
  end

  test "vault filters by section" do
    lease = users(:one).documents.create!(title: "Lease agreement")
    lease.sections << sections(:rights)
    users(:one).documents.create!(title: "Budget spreadsheet")

    get documents_path(section: "rights")
    assert_response :success
    assert_match "Lease agreement", response.body
    assert_no_match "Budget spreadsheet", response.body
  end

  test "shows a document with pending understanding" do
    document = users(:one).documents.create!(title: "Test results")
    get document_path(document)
    assert_response :success
    assert_match "Not analyzed yet", response.body
  end
end
