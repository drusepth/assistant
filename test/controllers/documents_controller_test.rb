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

  test "creating a document queues analysis when a model is configured" do
    assert_enqueued_with(job: AnalyzeDocumentJob) do
      post documents_path, params: { document: { title: "Lease" } }
    end
    assert Document.last.analysis_queued?
  end

  test "creating a document skips analysis without a configured model" do
    sign_in_as users(:outsider)
    assert_no_enqueued_jobs do
      post documents_path, params: { document: { title: "Lease" } }
    end
    assert_nil Document.last.analysis_status
  end

  test "analyze re-queues and is owner-only" do
    document = users(:one).documents.create!(title: "Lease")
    assert_enqueued_with(job: AnalyzeDocumentJob) { post analyze_document_path(document) }
    assert document.reload.analysis_queued?

    other = users(:two).documents.create!(title: "Bob's")
    post analyze_document_path(other)
    assert_response :not_found
  end

  test "applying a suggestion tags the document and consumes the suggestion" do
    document = users(:one).documents.create!(title: "Lease",
      suggested_sections: [ "renting", "money" ], analysis_status: "analyzed", summary: "A lease.")

    patch apply_suggestion_document_path(document, slug: "renting")

    document.reload
    assert_includes document.sections, sections(:renting)
    assert_equal [ "money" ], document.suggested_sections
  end
end
