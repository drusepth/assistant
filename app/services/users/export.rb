module Users
  # The portability half of the mission (D14/M4.2): your life must be
  # *takeable*, not just stored. Own data only — what's shared *with* you
  # belongs to its owner (D9) and is not yours to take. The archive is a
  # zip of JSON-lines files (one per primitive, section slugs inlined)
  # plus the raw bytes of your documents; the format is plain enough that
  # anything can import it. Whole-instance backup remains what it always
  # was: copy the storage/ volume.
  class Export
    FORMAT_VERSION = 1

    MODELS = {
      "events" => ->(user) { user.events },
      "tasks" => ->(user) { user.tasks },
      "documents" => ->(user) { user.documents },
      "people" => ->(user) { user.people },
      "goals" => ->(user) { user.goals },
      "notes" => ->(user) { user.notes },
      "suggestions" => ->(user) { user.suggestions }
    }.freeze

    OMITTED_COLUMNS = %w[ user_id ].freeze

    def initialize(user)
      @user = user
    end

    # Returns the zip as a StringIO, ready to attach or send.
    def call
      Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("manifest.json")
        zip.write(JSON.pretty_generate(manifest))

        MODELS.each do |name, scope|
          zip.put_next_entry("#{name}.jsonl")
          scope.call(@user).includes(:sections).find_each do |record|
            zip.write(row_for(record).to_json << "\n")
          end
        end

        @user.documents.includes(file_attachment: :blob).find_each do |document|
          next unless document.file.attached?

          zip.put_next_entry(file_entry_name(document))
          zip.write(document.file.download)
        end
      end.tap(&:rewind)
    end

    private
      def manifest
        {
          format: "assistant-export", version: FORMAT_VERSION,
          exported_at: Time.current.iso8601,
          user: { name: @user.name, email_address: @user.email_address },
          household: @user.household.name,
          contents: MODELS.keys.map { |name| "#{name}.jsonl" } + [ "files/" ]
        }
      end

      def row_for(record)
        row = record.attributes.except(*OMITTED_COLUMNS)
        row["sections"] = record.sections.map(&:slug) if record.respond_to?(:sections)
        row["file"] = file_entry_name(record) if record.is_a?(Document) && record.file.attached?
        row
      end

      def file_entry_name(document)
        "files/#{document.id}-#{document.file.filename}"
      end
  end
end
