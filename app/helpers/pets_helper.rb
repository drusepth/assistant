module PetsHelper
  # The pet who owns a lens, when the viewer can see her — what lets a
  # "Rex" chip open Rex's page rather than the bare list of her tagged items.
  # One query per render however many chips ask, and none for the seeded
  # taxonomy, which is never a pet's.
  def pet_for_lens(section)
    return nil unless section.custom? && Current.user

    @pets_by_lens ||= Pet.visible_to(Current.user).select(:id, :name, :section_id).index_by(&:section_id)
    @pets_by_lens[section.id]
  end

  # One line under a food: what she eats a day, when the bag runs out, what it
  # costs. Each clause appears only when its numbers exist — a food with no
  # bag size says what it can and stops, rather than printing an estimate
  # (D-pet-food-shelf).
  def pet_food_line(food)
    parts = []
    parts << food.daily_phrase if food.daily_phrase
    if (runs_out = food.runs_out_on)
      days = (runs_out - Date.current).to_i
      parts << if days.negative? then "bag ran out #{runs_out.strftime("%b %-d")}"
      elsif days.zero? then "bag runs out today"
      else "bag lasts to about #{runs_out.strftime("%b %-d")}"
      end
    elsif food.days_per_package
      parts << "a #{food.package_phrase} bag lasts about #{pluralize(food.days_per_package, "day")}"
    end
    parts << "#{money_amount(food.monthly_cost_cents)} a month" if food.monthly_cost_cents
    parts << "since #{food.started_on.strftime("%b %Y")}" if parts.empty?
    parts.join(" · ")
  end

  # The cost-of-care line, honest about what a ledger can't see. Silent when
  # there's no ledger at all: "$0 a year" on a pet page is a lie about a dog.
  def pet_cost_line(cost)
    return nil unless cost.monthly_average_cents

    "About #{money_amount(cost.monthly_average_cents)} a month over the last year — " \
      "what the ledger has filed under #{Pets::CostOfCare::CATEGORY_NAME}. Cash and mixed grocery trips aren't in it."
  end

  # ── Vaccines (D-pet-vaccinations) ───────────────────────────────────

  VACCINE_STATE_CHIPS = {
    current: [ "Current", "bg-sage-100 text-sage-700" ],
    due_soon: [ "Due soon", "bg-primary-200 text-primary-800" ],
    overdue: [ "Overdue", "bg-red-100 text-red-800" ],
    booked: [ "Booked", "bg-sage-200 text-sage-800" ],
    no_expiry: [ "No expiry recorded", "bg-stone-200 text-stone-700" ]
  }.freeze

  def vaccine_state_label(state) = VACCINE_STATE_CHIPS.fetch(state).first
  def vaccine_state_chip_classes(state) = VACCINE_STATE_CHIPS.fetch(state).second

  # One line under a vaccine on the card: when it runs out, then when it was
  # last given. A titer or exemption says so, because it is not a dose and a
  # reader relying on the card needs to know which it is looking at.
  def vaccine_entry_line(entry)
    latest = entry.latest
    when_phrase = case entry.state
    when :booked then "#{vaccine_until_phrase(latest)} · booked #{entry.booked_visit.starts_at.strftime("%b %-d")}"
    when :overdue then "Ran out #{latest.due_on.strftime("%b %-d, %Y")}"
    when :due_soon then "Due #{latest.due_on.strftime("%b %-d, %Y")}"
    when :current then vaccine_until_phrase(latest)
    else "No good-until date on record"
    end
    given = latest.dose? ? "last given #{latest.given_on.strftime("%b %-d, %Y")}" : "#{latest.kind_label.downcase} #{latest.given_on.strftime("%b %-d, %Y")}"
    [ when_phrase, given ].join(" · ")
  end

  def vaccine_until_phrase(dose)
    return "No good-until date on record" unless dose.due_on

    "Good until #{dose.due_on.strftime("%b %-d, %Y")}"
  end

  # The duration buttons' labels: "1 year", "3 years", "6 months".
  def vaccine_duration_options(durations)
    durations.map { |months| [ Pets::Vaccines.duration_label(months), months ] }
  end

  def vaccine_kind_options = PetVaccination::KINDS.map { |kind| [ PetVaccination::KIND_LABELS[kind], kind ] }
end
