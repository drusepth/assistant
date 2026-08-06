require "test_helper"

class ApplicationFormBuilderTest < ActionView::TestCase
  test "file_field renders full-width styled dropzone container" do
    builder = ApplicationFormBuilder.new(:document, Document.new, self, {})
    html = builder.file_field(:file, accept: ".pdf,.csv")

    assert_match 'class="file-input-dropzone group"', html
    assert_match 'data-controller="file-input"', html
    assert_match 'data-file-input-target="input"', html
    assert_match 'Click to choose a file', html
    assert_match 'Accepted formats: .pdf,.csv', html
  end
end
