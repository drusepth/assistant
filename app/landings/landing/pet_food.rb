module Landing
  # What a pet has been put on (D-pet-food-shelf): the prescription diet on
  # a discharge sheet, the bag on a receipt. Numbers land as printed; the
  # shelf's own validation and arithmetic apply exactly as to a typed row.
  class PetFood < Base
    self.description = "a food, diet or supplement a pet is on or has been prescribed"
    self.produces = "pet_foods"

    field :pet, "which pet", type: :ref, ref: :pet, required: true
    field :name, "the food, as printed", required: true
    field :brand
    field :form, "the kind of food", type: :choice, choices: ::PetFood::FORMS
    field :amount_per_day, "how much a day, only if stated", type: :decimal
    field :unit, "the unit the daily amount is in", type: :choice, choices: ::PetFood::UNITS
    field :package_amount, "the package size, only if stated", type: :decimal
    field :package_unit, "the unit the package is in", type: :choice, choices: ::PetFood::UNITS
    field :package_cost, "what one package costs, as printed, if stated", type: :decimal
    field :started_on, "when it started, only if stated", type: :date

    def self.label = "food shelf"

    def land!(attributes, sections:)
      pet = context.resolve(:pet, attributes["pet"])
      raise ActiveRecord::RecordNotFound, "that pet is gone or no longer shared" unless pet && pet.user_id == user.id

      pet.pet_foods.create!(
        name: attributes["name"], brand: attributes["brand"],
        form: attributes["form"].presence || "dry",
        amount_per_day: attributes["amount_per_day"], unit: attributes["unit"].presence || "g",
        package_amount: attributes["package_amount"], package_unit: attributes["package_unit"].presence || "g",
        package_cost_cents: attributes["package_cost"].present? ? (BigDecimal(attributes["package_cost"]) * 100).round : nil,
        started_on: parsed_date(attributes["started_on"]) || Date.current
      )
    end

    def duplicate_of(attributes)
      pet = context.resolve(:pet, attributes["pet"]) or return nil

      pet.pet_foods.current.where("LOWER(pet_foods.name) = ?", attributes["name"].to_s.downcase).first
    end

    def preview(attributes)
      pet = context.resolve(:pet, attributes["pet"])
      title = [ attributes["brand"], attributes["name"] ].compact_blank.join(" ")
      detail = [ pet && "for #{pet.name}", attributes["form"]&.humanize,
                 attributes["amount_per_day"] && "#{attributes["amount_per_day"]}#{attributes["unit"]} a day" ].compact_blank.join(" · ")
      Preview.new(kind: kind, title: title, detail: detail.presence, date: attributes["started_on"])
    end

    private
      def key_fields = %w[ pet name ]
  end
end
