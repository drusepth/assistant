module Pets
  # "What breed is she?" from one photo — the Breed box's helper, for the
  # household that adopted a cat and was never told. One call to the
  # household's vision-declared model (the rung Photos::Caption uses), and
  # the answer is only ever a suggestion: it fills the box, and nothing is
  # saved until the form is. The photo it looked at is not kept.
  #
  # A breed is a free-text field the owner edits, not a row the app files
  # things under, so the answer is cleaned (short, deduplicated, at most
  # three) rather than validated into a closed set. The prompt asks for the
  # honest answer where there is one: most cats are no breed at all, and
  # "Domestic shorthair" is a better guess than a pedigree read off a coat.
  class BreedGuess
    MAX_GUESSES = 3
    MAX_NAME = 60
    LIKELIHOODS = %w[ likely possible ].freeze
    # What the model sees: resized and stripped of metadata, whatever came in.
    VARIANT = { resize_to_limit: [ 1024, 1024 ], format: :webp, saver: { quality: 85, strip: true } }.freeze

    Guess = Data.define(:name, :likelihood)
    Result = Data.define(:guesses, :note)

    # species: a Pet::SPECIES slug. image: WEBP bytes (see .image_bytes).
    def initialize(species:, image:, profile:)
      @species = species
      @image = image
      @profile = profile
    end

    def call
      response = @profile.client.chat(messages, json: true)
      Result.new(guesses: clean(response["breeds"]), note: response["note"].to_s.squish.truncate(240).presence)
    end

    # The bytes of an upload or a stored attachment, as the model is sent
    # them. An upload is processed here and dropped; an attachment gets a
    # variant like any other.
    def self.image_bytes(upload: nil, attachment: nil)
      if upload
        ImageProcessing::Vips.source(upload.tempfile.path)
          .resize_to_limit(*VARIANT[:resize_to_limit]).convert("webp")
          .saver(**VARIANT[:saver]).call.read
      else
        attachment.variant(VARIANT).processed.download
      end
    end

    private
      def messages
        [
          { role: "system", content: system_prompt },
          { role: "user", content: [
            { type: "text", text: "The animal is a #{species_label}. Which breed does it look like?" },
            { type: "image_url", image_url: { url: "data:image/webp;base64,#{Base64.strict_encode64(@image)}" } }
          ] }
        ]
      end

      def species_label = Pet::SPECIES_LABELS.fetch(@species, "pet").downcase

      def system_prompt
        <<~PROMPT
          You help a pet owner fill in the "breed" box on their pet's record, from one photo.
          Name the breed or type the animal most looks like, as an owner would write it.
          Be honest about what a photo can show:
          - Most cats have no pedigree. Unless the cat plainly shows a breed's features, answer
            "Domestic shorthair", "Domestic medium hair" or "Domestic longhair".
          - A dog that looks like a cross is a mix: say so, as "Labrador mix" or "Shepherd mix".
          - If the photo shows no animal of that kind, or too little of it to judge, return no breeds
            and say why in the note.
          Respond with a JSON object:
          {"breeds": [{"name": "...", "likelihood": "likely" | "possible"}], "note": "..."}
          At most #{MAX_GUESSES} breeds, most likely first. The note is one short, plain sentence
          (what in the photo points that way, or why you can't tell), or empty.
        PROMPT
      end

      def clean(breeds)
        Array(breeds).filter_map do |breed|
          next unless breed.is_a?(Hash)

          name = breed["name"].to_s.squish
          next if name.blank? || name.length > MAX_NAME

          Guess.new(name: name, likelihood: LIKELIHOODS.include?(breed["likelihood"]) ? breed["likelihood"] : "possible")
        end.uniq { |guess| guess.name.downcase }.first(MAX_GUESSES)
      end
  end
end
