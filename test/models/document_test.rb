require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  test "title defaults to a cleaned-up file name" do
    document = users(:one).documents.new
    document.file.attach(io: StringIO.new("x"), filename: "lease-agreement_2026.pdf", content_type: "application/pdf")
    document.save!

    assert_equal "Lease agreement 2026", document.title
  end

  test "a given title beats the file name" do
    document = users(:one).documents.new(title: "Our lease")
    document.file.attach(io: StringIO.new("x"), filename: "scan0001.pdf", content_type: "application/pdf")
    document.save!

    assert_equal "Our lease", document.title
  end

  test "still requires a title without a file" do
    assert_not users(:one).documents.new.valid?
  end
end
