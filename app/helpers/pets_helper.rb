module PetsHelper
  # One line under a food: what she eats a day, when the bag runs out, what it
  # costs. Each clause appears only when its numbers exist — a food with no
  # bag size says what it can and stops, rather than printing an estimate
  # (D-pet-food-shelf).
  def pet_food_line(food)
    parts = []
    parts << "#{number_with_precision(food.amount_per_day, precision: 2, strip_insignificant_zeros: true)}#{food.unit} a day" if food.amount_per_day
    if (runs_out = food.runs_out_on)
      days = (runs_out - Date.current).to_i
      parts << if days.negative? then "bag ran out #{runs_out.strftime("%b %-d")}"
      elsif days.zero? then "bag runs out today"
      else "bag lasts to about #{runs_out.strftime("%b %-d")}"
      end
    elsif food.days_per_package
      parts << "a bag lasts about #{pluralize(food.days_per_package, "day")}"
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
end
