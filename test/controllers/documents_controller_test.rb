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

  test "uploads with no title, falling back to the file name" do
    post documents_path, params: { document: { file: fixture_file_upload("sample.txt", "text/plain") } }

    assert_equal "Sample", Document.last.title
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

  test "a photographed document shows its picture on its page" do
    document = users(:one).documents.create!(title: "Vet report")
    attach_image(document)

    get document_path(document)
    assert_response :success
    assert_select "img[alt='Vet report']"

    plain = users(:one).documents.create!(title: "Lease")
    get document_path(plain)
    assert_select "img[alt='Lease']", count: 0
  end

  test "the document page and vault rows offer the decode-letter front door" do
    document = users(:one).documents.create!(title: "Scary envelope")

    get document_path(document)
    assert_select "a[href=?]", new_tool_run_path("decode_letter", inputs: { document_id: document.id }),
      text: "Decode this"

    get documents_path
    assert_select "a[href=?]", new_tool_run_path("decode_letter", inputs: { document_id: document.id }),
      text: "Decode"
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

  # ── The review page (D-document-intake) ────────────────────────────────

  def proposing_document(user: users(:one))
    document = user.documents.create!(title: "Vet discharge sheet", analysis_status: "analyzed", summary: "Rex's visit.")
    document.sections << sections(:health)
    document.update!(landings: [
      { "kind" => "event", "fingerprint" => "event:rex-vaccinations:2026-08-12", "status" => "proposed",
        "attributes" => { "title" => "Rex — vaccinations", "on" => "2026-08-12", "description" => "Rabies booster" } },
      { "kind" => "person", "fingerprint" => "person:dr-alvarez", "status" => "proposed",
        "attributes" => { "name" => "Dr. Alvarez", "relationship" => "Vet", "phone" => "555-0100" } },
      { "kind" => "task", "fingerprint" => "task:book-a-follow-up", "status" => "proposed",
        "attributes" => { "title" => "Book a follow-up" } }
    ])
    document
  end

  test "the document page fronts the review while anything is proposed" do
    document = proposing_document
    get document_path(document)
    assert_select "a[href=?]", review_document_path(document), text: "Review 3"
  end

  test "the review page renders each landing as a prefilled, editable card" do
    document = proposing_document
    get review_document_path(document)
    assert_response :success
    assert_select "input[name='landings[0][keep]'][checked]"
    assert_select "input[name='landings[0][attributes][title]'][value='Rex — vaccinations']"
    assert_select "input[name='landings[0][attributes][on]'][value='2026-08-12']"
    assert_select "textarea[name='landings[0][attributes][description]']", text: /Rabies booster/
    assert_select "input[name='landings[1][attributes][name]'][value='Dr. Alvarez']"
    assert_match "nothing is saved yet", response.body.downcase
  end

  test "the review page is the owner's" do
    document = proposing_document(user: users(:two))
    get review_document_path(document)
    assert_response :not_found
  end

  test "saving lands the ticked cards with the user's edits, skips the rest, and records provenance" do
    document = proposing_document

    assert_difference [ "Event.count", "Person.count" ], 1 do
      assert_no_difference "Task.count" do
        post land_document_path(document), params: { landings: {
          "0" => { keep: "1", attributes: { title: "Rex — rabies booster", on: "2026-08-13", description: "Rabies booster" } },
          "1" => { keep: "1", attributes: { name: "Dr. Alvarez", relationship: "Vet", phone: "555-0100" } }
          # "2" left out: unticked
        } }
      end
    end
    assert_redirected_to document_path(document)
    assert_match "Saved 2 things", flash[:notice]

    event = Event.last
    assert_equal "Rex — rabies booster", event.title, "the edit won over the proposal"
    assert_equal Date.new(2026, 8, 13), event.starts_at.to_date
    assert_equal [ sections(:health) ], event.sections.to_a, "the landing inherited the document's filing"

    document.reload
    assert_equal %w[ saved saved skipped ], document.landings.map { |entry| entry["status"] }
    assert_equal "Rex — rabies booster", document.landings.first.dig("attributes", "title")
    assert_equal [ event, Person.last ], document.produced_items
    assert_equal document, DocumentItem.source_for(event)
    assert_not document.landings_to_review?
  end

  test "a card that fails validation re-renders the page with its error, and nothing lands" do
    document = proposing_document

    assert_no_difference [ "Event.count", "Person.count" ] do
      post land_document_path(document), params: { landings: {
        "0" => { keep: "1", attributes: { title: "Rex — vaccinations", on: "next tuesday" } },
        "1" => { keep: "1", attributes: { name: "Dr. Alvarez" } }
      } }
    end
    assert_response :unprocessable_entity
    assert_match "isn&#39;t a date", response.body
    assert_equal %w[ proposed proposed proposed ], document.reload.landings.map { |entry| entry["status"] }
  end

  test "skip all saves nothing and remembers every card as skipped" do
    document = proposing_document
    post land_document_path(document)
    assert_redirected_to document_path(document)
    assert_equal %w[ skipped skipped skipped ], document.reload.landings.map { |entry| entry["status"] }
    get review_document_path(document)
    assert_match "Nothing left to review", response.body
  end

  test "a landing that duplicates something the user already has renders unticked with a link to it" do
    document = proposing_document
    existing = users(:one).events.create!(title: "Rex — vaccinations", starts_at: Time.zone.local(2026, 8, 12, 10))

    get review_document_path(document)
    assert_select "input[name='landings[0][keep]']:not([checked])"
    assert_select "a[href=?]", event_path(existing)
    assert_select "input[name='landings[1][keep]'][checked]"
  end

  test "an amendment card shows old → new, and saving it updates the record rather than adding one" do
    rex = create_pet(user: users(:one), weight_kg: 31.2)
    document = users(:one).documents.create!(title: "Vet discharge sheet", analysis_status: "analyzed")
    document.update!(landings: [
      { "kind" => "pet_facts", "fingerprint" => "pet_facts:rex:32-6", "status" => "proposed",
        "attributes" => { "pet" => rex.section.slug, "weight_kg" => "32.6" } }
    ])

    get review_document_path(document)
    assert_response :success
    assert_match "Weight: 31.2 kg → 32.6 kg", response.body
    assert_select "select[name='landings[0][attributes][pet]'] option[selected][value=?]", rex.section.slug

    assert_no_difference "Pet.count" do
      post land_document_path(document), params: { landings: { "0" => { keep: "1", attributes: { pet: rex.section.slug, weight_kg: "32.8" } } } }
    end
    assert_equal 32.8, rex.reload.weight_kg.to_f, "the edit on the card won"
    assert_equal [ rex ], document.reload.produced_items
  end

  test "a row saved from a document says where it came from" do
    document = users(:one).documents.create!(title: "Vet discharge sheet")
    event = users(:one).events.create!(title: "Rex — vaccinations", starts_at: Time.current)
    document.document_items.create!(item: event, fingerprint: "event:x")

    get event_path(event)
    assert_match "From", response.body
    assert_select "a[href=?]", document_path(document), text: "Vet discharge sheet"
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
