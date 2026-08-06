require "test_helper"

class ExportJobTest < ActiveJob::TestCase
  test "builds a zip of the user's own data with sections inlined and files included" do
    task = users(:one).tasks.create!(title: "Renew passport")
    task.sections << sections(:rights)
    users(:two).tasks.create!(title: "Bob's private task")
    shared = users(:two).notes.create!(body: "Shared with Alice")
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: shared)
    document = users(:one).documents.create!(title: "Lease")
    document.file.attach(io: StringIO.new("PDF BYTES"), filename: "lease.pdf", content_type: "application/pdf")

    ExportJob.perform_now(users(:one))

    assert users(:one).export_archive.attached?
    entries = {}
    Zip::File.open_buffer(StringIO.new(users(:one).export_archive.download)) do |zip|
      zip.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end

    manifest = JSON.parse(entries["manifest.json"])
    assert_equal "assistant-export", manifest["format"]

    tasks = entries["tasks.jsonl"].lines.map { |line| JSON.parse(line) }
    assert_equal [ "Renew passport" ], tasks.map { |row| row["title"] }, "own data only — never another member's"
    assert_equal [ "rights" ], tasks.first["sections"]

    notes = entries["notes.jsonl"].to_s.lines
    assert_empty notes, "shared-with-you items belong to their owner (D9)"

    document_row = JSON.parse(entries["documents.jsonl"].lines.first)
    assert_equal "files/#{document.id}-lease.pdf", document_row["file"]
    assert_equal "PDF BYTES", entries["files/#{document.id}-lease.pdf"]
  end

  test "the settings button enqueues and the page offers the download" do
    integration = ActionDispatch::Integration::Session.new(Rails.application)
    integration.post "/session", params: { email_address: users(:one).email_address, password: "password" }

    assert_enqueued_with job: ExportJob do
      integration.post "/export"
    end

    ExportJob.perform_now(users(:one))
    integration.get "/settings"
    assert_match "Download", integration.response.body
  end
end
