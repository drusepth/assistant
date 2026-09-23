require "test_helper"

class ApplicationFormBuilderTest < ActionView::TestCase
  test "file_field renders full-width styled dropzone container" do
    builder = ApplicationFormBuilder.new(:document, Document.new, self, {})
    html = builder.file_field(:file, accept: ".pdf,.csv")

    assert_match 'class="file-input-dropzone group"', html
    assert_match 'data-controller="file-input"', html
    assert_match 'data-file-input-target="input"', html
    assert_match "Click to choose a file", html
    assert_match "Accepted formats: .pdf,.csv", html
  end

  test "telephone_field shows the stored number masked and wires the mask" do
    builder = ApplicationFormBuilder.new(:person, Person.new(phone: "+15036149061"), self, {})
    html = builder.telephone_field(:phone)

    assert_match 'value="(503) 614-9061"', html
    assert_match 'data-controller="phone-input"', html
    assert_match 'inputmode="tel"', html
    assert_match "pattern=", html
  end

  test "telephone_field leaves a number it couldn't read submittable" do
    builder = ApplicationFormBuilder.new(:person, Person.new(phone: "555-1234"), self, {})
    html = builder.telephone_field(:phone)

    assert_match 'value="555-1234"', html
    assert_no_match "pattern=", html
  end
end
