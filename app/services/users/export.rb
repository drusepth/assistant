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
      "photos" => ->(user) { user.photos },
      "albums" => ->(user) { user.albums },
      "suggestions" => ->(user) { user.suggestions },
      "spending_accounts" => ->(user) { user.spending_accounts },
      "budget_categories" => ->(user) { user.budget_categories },
      "spending_rules" => ->(user) { user.spending_rules },
      "credentials" => ->(user) { user.credentials }
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
          records = scope.call(@user)
          records = records.includes(:sections) if records.klass.reflect_on_association(:sections)
          records.find_each do |record|
            zip.write(row_for(record).to_json << "\n")
          end
        end

        # The ledger's carve-out (D-spending-mirror): unlike the email
        # mirror, spending history often has no other durable copy — bank
        # portals age statements out — so it leaves with the user as plain CSV.
        zip.put_next_entry("spending.csv")
        zip.write(spending_csv)

        @user.documents.includes(file_attachment: :blob).find_each do |document|
          next unless document.file.attached?

          zip.put_next_entry(file_entry_name(document))
          zip.write(document.file.download)
        end

        # Photo originals, untouched — EXIF included; it's the owner's own
        # data leaving with them (stripping only applies to shared viewers).
        @user.photos.includes(image_attachment: :blob).find_each do |photo|
          next unless photo.image.attached?

          zip.put_next_entry(photo_entry_name(photo))
          zip.write(photo.image.download)
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
          contents: MODELS.keys.map { |name| "#{name}.jsonl" } + [ "spending.csv", "files/", "photo_files/" ],
          credentials: "metadata only — this job can't hold your vault key (PASSWORDS_PLAN §4.7); export secrets from the Passwords page while unlocked"
        }
      end

      def row_for(record)
        row = record.attributes.except(*OMITTED_COLUMNS)
        # The vault's rule (D-passwords-vault): ciphertext never leaves in a
        # background job — metadata only here.
        row = row.except("secrets_ciphertext") if record.is_a?(Credential)
        row["sections"] = record.sections.map(&:slug) if record.respond_to?(:sections)
        row["file"] = file_entry_name(record) if record.is_a?(Document) && record.file.attached?
        row["file"] = photo_entry_name(record) if record.is_a?(Photo) && record.image.attached?
        row["photo_ids"] = record.photo_ids if record.is_a?(Album)
        row
      end

      def file_entry_name(document)
        "files/#{document.id}-#{document.file.filename}"
      end

      def photo_entry_name(photo)
        "photo_files/#{photo.id}-#{photo.image.filename}"
      end

      def spending_csv
        accounts = @user.spending_accounts.index_by(&:id)
        categories = @user.budget_categories.index_by(&:id)

        CSV.generate do |csv|
          csv << %w[ date amount_cents currency account category merchant descriptor source transfer ]
          SpendingTransaction.where(user_id: @user.id).order(:occurred_on, :id).each do |row|
            csv << [
              row.occurred_on.iso8601, row.amount_cents, @user.household.currency,
              accounts[row.spending_account_id]&.name, categories[row.budget_category_id]&.name,
              row.merchant, row.descriptor, row.source, row.transfer
            ]
          end
        end
      end
  end
end
