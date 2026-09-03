module Documents
  # What the model gets to read of a document (INTAKE_PLAN §2, W1). Four
  # rungs, cheapest first:
  #
  #   1. a text file — the bytes;
  #   2. a PDF with a text layer — pdf-reader's extraction;
  #   3. an image — a resized, metadata-stripped WEBP as a data URL, through
  #      the same vision path Photos::Caption uses;
  #   4. a PDF with *no* text layer (a scan) — its first pages rendered to
  #      images through vips' PDF loader, capped, then rung 3.
  #
  # Rungs 3 and 4 need a model the admin has declared vision-capable. Without
  # one the document says so — "this model can't read images" — rather than
  # guessing from the title (the D-no-keyword-logic no-model rule): a
  # confident summary of a file nobody read is worse than an honest absence.
  class Read
    class Unreadable < StandardError; end

    TEXT_TYPES = %w[ text/plain text/markdown text/csv application/json ].freeze
    # Enough pages to read a discharge sheet or a lease's front matter; a
    # forty-page scan is a bundle, and reading all of it is a later rung
    # (INTAKE_PLAN §9, multi-photo documents).
    MAX_PAGES = 3
    RENDER_DPI = 110
    MAX_EDGE = 1600

    NO_VISION = "This model can't read images. Turn on vision in Settings if it can, " \
                "or upload a PDF or text file instead.".freeze

    # `text` is what a text rung produced (nil for images); `images` are
    # data URLs for the vision call, in page order.
    Content = Data.define(:text, :images) do
      def images? = images.any?
      def blank? = text.blank? && images.empty?
    end

    def initialize(document, vision: false)
      @document = document
      @vision = vision
    end

    def call
      return Content.new(text: nil, images: []) unless file.attached?

      if content_type == "application/pdf"
        pdf
      elsif content_type.start_with?("image/")
        image
      elsif TEXT_TYPES.include?(content_type) || content_type.start_with?("text/")
        Content.new(text: file.download.force_encoding(Encoding::UTF_8).scrub, images: [])
      else
        raise Unreadable, "Text can't be extracted from #{content_type} files yet — " \
                          "PDF, plain-text and image files are supported."
      end
    end

    private
      def file = @document.file
      def content_type = file.content_type.to_s

      def pdf
        text = file.open { |io| PDF::Reader.new(io).pages.map(&:text).join("\n").scrub }
        return Content.new(text: text, images: []) if text.strip.present?

        # No text layer: it's a scan, and only a vision model can read one.
        unless @vision
          raise Unreadable, "This PDF is a scan with no text in it, and this model can't read images. " \
                            "Turn on vision in Settings if it can, or upload a PDF with selectable text."
        end
        Content.new(text: nil, images: rendered_pages)
      rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
        raise Unreadable, "This PDF couldn't be read: #{e.message}"
      end

      def image
        raise Unreadable, NO_VISION unless @vision

        Content.new(text: nil, images: [ data_url(resized_image) ])
      rescue ActiveStorage::Error, Vips::Error => e
        raise Unreadable, "Couldn't read this image — is it a supported format? (#{e.message.lines.first.to_s.strip})"
      end

      # The model sees a bounded, stripped derivative, never the original —
      # the Photos rule, for the same reason (a phone photo carries EXIF).
      def resized_image
        file.variant(resize_to_limit: [ MAX_EDGE, MAX_EDGE ], format: :webp,
          saver: { quality: 85, strip: true }).processed.download
      end

      # Active Storage blocks every libvips loader that hasn't been fuzzed,
      # and the PDF loader (poppler) is one of them. It is re-enabled here,
      # for PDFs only and only on the path that needs it, because the input
      # is a file an authenticated household member uploaded to their own
      # instance — and the same bytes have already been through pdf-reader
      # (which found no text) before the loader sees them. Idempotent, so
      # it doesn't matter what order Active Storage's own block ran in.
      def rendered_pages
        Vips.block("VipsForeignLoadPdf", false)
        file.open do |io|
          pages = Vips::Image.pdfload(io.path, page: 0, n: 1).get("n-pages").to_i.clamp(1, MAX_PAGES)
          pages.times.map do |index|
            page = Vips::Image.pdfload(io.path, page: index, n: 1, dpi: RENDER_DPI)
            page = page.thumbnail_image(MAX_EDGE) if [ page.width, page.height ].max > MAX_EDGE
            data_url(page.write_to_buffer(".webp[Q=85,strip]"))
          end
        end
      rescue Vips::Error => e
        raise Unreadable, "This scanned PDF couldn't be rendered: #{e.message.lines.first.to_s.strip}"
      end

      def data_url(bytes) = "data:image/webp;base64,#{Base64.strict_encode64(bytes)}"
  end
end
