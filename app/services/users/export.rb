# Explicit, like datasets/oews_workbook.rb: the Gemfile's `require: "zip"`
# only fires for processes that boot the current bundle, and this class is
# reachable from a long-lived worker that may predate the gem.
require "zip"

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
      "recipes" => ->(user) { user.recipes },
      # A pet and her diet history leave with her owner (D14) — the diet is
      # the half a vet asks for, so it is not an ornament of the pet row.
      "pets" => ->(user) { user.pets },
      "pet_foods" => ->(user) { PetFood.where(pet_id: user.pets.select(:id)) },
      # Her vaccine record leaves with her too (D-pet-vaccinations): it is
      # the first thing a new vet or a new kennel asks for.
      "pet_vaccinations" => ->(user) { PetVaccination.where(pet_id: user.pets.select(:id)) },
      "recipe_books" => ->(user) { user.recipe_books },
      # The kitchens you own and everything in them (D-kitchen): its rows
      # have no owner but the kitchen, so they leave with its owner.
      "kitchens" => ->(user) { user.kitchens },
      "shopping_lists" => ->(user) { ShoppingList.where(kitchen: user.kitchens) },
      "shopping_list_items" => ->(user) { ShoppingListItem.where(shopping_list: ShoppingList.where(kitchen: user.kitchens)) },
      "pantry_items" => ->(user) { PantryItem.where(kitchen: user.kitchens) },
      "foods" => ->(user) { Food.where(kitchen: user.kitchens) },
      "meals" => ->(user) { Meal.where(kitchen: user.kitchens) },
      "diners" => ->(user) { Diner.where(kitchen: user.kitchens) },
      "suggestions" => ->(user) { user.suggestions },
      "spending_accounts" => ->(user) { user.spending_accounts },
      "budget_categories" => ->(user) { user.budget_categories },
      "spending_rules" => ->(user) { user.spending_rules },
      "credentials" => ->(user) { user.credentials },
      # The subscriptions, not the river (D-feed-reader): a reading list is
      # yours and takes a line each; the items behind it are a cache of
      # somebody else's site, and are re-fetched by whatever you import
      # this into.
      "feeds" => ->(user) { user.feeds }
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

        @user.recipes.includes(image_attachment: :blob).find_each do |recipe|
          next unless recipe.image.attached?

          zip.put_next_entry(recipe_image_entry_name(recipe))
          zip.write(recipe.image.download)
        end

        # Your address book's faces travel with it (D-contact-photos), by
        # the same rule as the rest of the archive: originals, not variants.
        @user.people.includes(avatar_attachment: :blob).find_each do |person|
          next unless person.avatar.attached?

          zip.put_next_entry(contact_photo_entry_name(person))
          zip.write(person.avatar.download)
        end

        # Your face is yours too (D-user-avatars) — the original, not the
        # square the app renders.
        if @user.avatar.attached?
          zip.put_next_entry(avatar_entry_name)
          zip.write(@user.avatar.download)
        end
      end.tap(&:rewind)
    end

    private
      def manifest
        {
          format: "assistant-export", version: FORMAT_VERSION,
          exported_at: Time.current.iso8601,
          user: { name: @user.name, email_address: @user.email_address,
                  job_title: @user.job_title, employer: @user.employer,
                  avatar: (avatar_entry_name if @user.avatar.attached?) }.compact,
          household: @user.household.name,
          contents: MODELS.keys.map { |name| "#{name}.jsonl" } + [ "spending.csv", "files/", "photo_files/", "recipe_files/", "contact_photos/" ],
          credentials: "metadata only — this job can't hold your vault key (PASSWORDS_PLAN §4.7); export secrets from the Passwords page while unlocked",
          diary: "not included at all — a diary has no metadata tier worth carrying, and even its dates say more than an archive should (DIARY_PLAN §6); export it from the Diary page while unlocked"
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
        row["photo"] = contact_photo_entry_name(record) if record.is_a?(Person) && record.avatar.attached?
        row["photo_ids"] = record.photo_ids if record.is_a?(Album)
        # A recipe without its ingredients isn't a recipe: the rows travel
        # inline, raw line included, so an importer can take either the
        # parse or the text the cook typed.
        if record.is_a?(Recipe)
          row["ingredients"] = record.recipe_ingredients.map { |line| line.attributes.except("id", "recipe_id", "created_at", "updated_at") }
          row["image"] = recipe_image_entry_name(record) if record.image.attached?
        end
        row["recipe_ids"] = record.recipe_ids if record.is_a?(RecipeBook)
        row
      end

      def file_entry_name(document)
        "files/#{document.id}-#{document.file.filename}"
      end

      def photo_entry_name(photo)
        "photo_files/#{photo.id}-#{photo.image.filename}"
      end

      def recipe_image_entry_name(recipe)
        "recipe_files/#{recipe.id}-#{recipe.image.filename}"
      end

      def contact_photo_entry_name(person)
        "contact_photos/#{person.id}-#{person.avatar.filename}"
      end

      def avatar_entry_name
        "avatar-#{@user.avatar.filename}"
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
