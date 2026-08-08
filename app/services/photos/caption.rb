module Photos
  # The optional AI garnish over photos (D30/W5): one multimodal call to the
  # household's vision-declared model for a plain caption plus suggested
  # section tags — suggestions are only ever suggestions (trust ladder, D6).
  # The model sees the stripped :large variant, never the EXIF-bearing
  # original.
  class Caption
    MAX_SUGGESTIONS = 3

    Result = Data.define(:caption, :section_slugs)

    def initialize(photo:, profile:)
      @photo = photo
      @profile = profile
    end

    def call
      response = @profile.client.chat(messages, json: true)

      Result.new(
        caption: response["caption"].to_s.strip,
        section_slugs: valid_slugs(response["sections"])
      )
    end

    private
      def messages
        [
          { role: "system", content: system_prompt },
          { role: "user", content: [
            { type: "text", text: user_prompt },
            { type: "image_url", image_url: { url: data_url } }
          ] }
        ]
      end

      def data_url
        "data:image/webp;base64,#{Base64.strict_encode64(@photo.image.variant(:large).processed.download)}"
      end

      def system_prompt
        <<~PROMPT
          You are the photo-understanding feature of a private, self-hosted life assistant.
          Describe the photo for the household's own library: one or two plain, warm,
          factual sentences — no speculation about who people are or how anyone feels.
          Also suggest which life sections the photo belongs to.
          Respond with a JSON object: {"caption": "...", "sections": ["slug", ...]}.
          Choose at most #{MAX_SUGGESTIONS} sections, only from the provided list, ordered by relevance.
        PROMPT
      end

      def user_prompt
        parts = []
        parts << "Title: #{@photo.title}" if @photo.title.present?
        parts << "Taken: #{@photo.taken_at.strftime("%B %-d, %Y")}"
        parts << "Available sections (slug — meaning):\n#{taxonomy}"
        parts.join("\n\n")
      end

      def taxonomy
        Section.order(:parent_id, :position).map { |section| "#{section.slug} — #{section.qualified_name}" }.join("\n")
      end

      def valid_slugs(slugs)
        known = Section.where(slug: Array(slugs).map(&:to_s)).pluck(:slug)
        Array(slugs).map(&:to_s).select { |slug| known.include?(slug) }.first(MAX_SUGGESTIONS)
      end
  end
end
