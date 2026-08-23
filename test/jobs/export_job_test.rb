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

  # A recipe you can't cook from isn't an export: the parsed lines and the
  # raw text the cook typed both travel (D-recipe-primitive).
  test "recipes leave with their ingredients and their books" do
    recipe = users(:one).recipes.create!(title: "Lentil soup", servings: 4,
      ingredients_text: "200 g red lentils\n2 onions, chopped")
    book = users(:one).recipe_books.create!(title: "Soups")
    book.recipe_book_entries.create!(recipe: recipe)

    ExportJob.perform_now(users(:one))

    entries = {}
    Zip::File.open_buffer(StringIO.new(users(:one).export_archive.download)) do |zip|
      zip.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end

    row = JSON.parse(entries["recipes.jsonl"].lines.first)
    assert_equal "Lentil soup", row["title"]
    assert_equal [ "200 g red lentils", "2 onions, chopped" ], row["ingredients"].map { |line| line["raw"] }
    assert_equal "red lentil", row["ingredients"].first["item_key"]

    book_row = JSON.parse(entries["recipe_books.jsonl"].lines.first)
    assert_equal [ recipe.id ], book_row["recipe_ids"]
  end

  test "your avatar leaves with you, original bytes and all (D-user-avatars)" do
    users(:one).avatar.attach(io: StringIO.new("JPEG BYTES"), filename: "me.jpg", content_type: "image/jpeg")

    ExportJob.perform_now(users(:one))

    entries = {}
    Zip::File.open_buffer(StringIO.new(users(:one).export_archive.download)) do |zip|
      zip.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end

    assert_equal "JPEG BYTES", entries["avatar-me.jpg"]
    assert_equal "avatar-me.jpg", JSON.parse(entries["manifest.json"]).dig("user", "avatar")
  end

  # D-vault-crypto: key material must never ride the job queue, so the
  # archive carries credential *metadata* and the Passwords page owns the
  # in-request secrets export.
  test "credentials export as metadata only — never ciphertext" do
    Keyring.initialize_for(users(:one), "password")
    credential = users(:one).credentials.create!(name: "Bank", kind: "login", username: "drew")
    credential.write_secrets!({ "password" => "distinctive-plaintext" })

    ExportJob.perform_now(users(:one))

    entries = {}
    Zip::File.open_buffer(StringIO.new(users(:one).export_archive.download)) do |zip|
      zip.each { |entry| entries[entry.name] = entry.get_input_stream.read }
    end

    row = JSON.parse(entries["credentials.jsonl"].lines.first)
    assert_equal "Bank", row["name"]
    assert_not row.key?("secrets_ciphertext")
    assert_no_match(/distinctive-plaintext/, entries["credentials.jsonl"])
    assert_match(/metadata only/, JSON.parse(entries["manifest.json"])["credentials"])
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
