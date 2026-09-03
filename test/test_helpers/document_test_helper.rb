# Files for document tests (INTAKE_PLAN W1). A PDF is built by hand here
# rather than checked in, so a test can say whether it carries a text layer
# — the difference between the pdf-reader rung and the scan rung — in one
# argument instead of two binary fixtures nobody can read in a diff.
module DocumentTestHelper
  # A one-page PDF. With `text:` it carries a real text layer (Helvetica,
  # one line) that pdf-reader extracts; without, it is a blank page — what
  # a scanner produces, minus the picture.
  def pdf_bytes(text: nil)
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
    ]
    if text
      stream = "BT /F1 12 Tf 20 60 Td (#{text}) Tj ET"
      objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
      objects << "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
      objects << "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    else
      objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] >>"
    end

    out = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |body, index|
      offset = out.bytesize
      out << "#{index + 1} 0 obj\n#{body}\nendobj\n"
      offset
    end
    xref = out.bytesize
    out << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| out << format("%010d 00000 n \n", offset) }
    out << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    out
  end

  def attach_pdf(document, text: nil)
    document.file.attach(io: StringIO.new(pdf_bytes(text: text)), filename: "scan.pdf", content_type: "application/pdf")
  end

  def attach_image(document, filename: "photo.jpg")
    document.file.attach(io: file_fixture(filename).open, filename: filename, content_type: "image/jpeg")
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include DocumentTestHelper
end
