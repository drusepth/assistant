require "test_helper"

class ApplicationFormBuilderTest < ActionView::TestCase
  test "file_field renders full-width styled dropzone container" do
    builder = ApplicationFormBuilder.new(:document, Document.new, self, {})
    html = builder.file_field(:file, accept: ".pdf,.csv")

    assert_match 'class="file-input-dropzone group"', html
    assert_match 'data-controller="file-input"', html
    assert_match 'data-file-input-target="input"', html
    assert_match "Click to choose a file", html
    assert_match "Accepted formats: PDF or CSV", html
    assert_match 'accept=".pdf,.csv"', html, "the input keeps the real list"
  end

  test "the accepted-formats line is words, not a MIME list" do
    assert_equal "photos or PDF", ApplicationFormBuilder.accept_phrase("image/*,application/pdf")
    assert_equal "ICS, ICAL or CSV", ApplicationFormBuilder.accept_phrase(".ics,.ical,.csv,text/calendar,text/csv"),
      "a MIME type that repeats an extension is dropped"
    assert_equal "PNG, JPEG, WebP or GIF", ApplicationFormBuilder.accept_phrase("image/png, image/jpeg, image/webp, image/gif")

    builder = ApplicationFormBuilder.new(:document, Document.new, self, {})
    html = builder.file_field(:file, accept: "image/*", accept_label: "a photo of the label")
    assert_match "Accepted formats: a photo of the label", html
    assert_no_match "accept_label", html
  end

  test "telephone_field shows the stored number masked and wires the mask" do
    builder = ApplicationFormBuilder.new(:person, Person.new(phone: "+15035550142"), self, {})
    html = builder.telephone_field(:phone)

    assert_match 'value="(503) 555-0142"', html
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

  test "a number saved before the mask arms the pattern only once it's retyped" do
    builder = ApplicationFormBuilder.new(:person, Person.new(phone: "555-1234"), self, {})

    assert_match "data-phone-input-pattern-value=", builder.telephone_field(:phone)
  end
end
