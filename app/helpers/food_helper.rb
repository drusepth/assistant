module FoodHelper
  # A list's open lines as [[aisle, items], ...] — see group_by_aisle.
  def shopping_list_groups(items, kitchen)
    group_by_aisle(items, kitchen) { |item| item.food&.aisle }
  end

  # Records as [[aisle, records], ...] in the kitchen's aisle order, those
  # with no aisle last under nil, each group keeping the order given.
  def group_by_aisle(records, kitchen, &aisle_of)
    order = kitchen.aisles_in_order
    records.group_by(&aisle_of)
      .sort_by { |aisle, _| aisle ? order.index(aisle) || order.size : order.size + 1 }
  end

  # "Use by Thu" / "went off Tuesday" / "opened 3 days ago" — dates in
  # words, the way you'd say them standing at the fridge.
  def pantry_item_dates(item, today: Date.current)
    parts = []
    if item.expires_on
      parts << if item.expires_on < today then "went off #{relative_day(item.expires_on, today)}"
      elsif item.expires_on == today then "use today"
      else "use by #{relative_day(item.expires_on, today)}"
      end
    end
    if item.opened_on
      days = (today - item.opened_on).to_i
      parts << (days.zero? ? "opened today" : "opened #{pluralize(days, "day")} ago")
    end
    parts.join(" · ")
  end

  def relative_day(date, today = Date.current)
    return "tomorrow" if date == today + 1
    return "yesterday" if date == today - 1
    return date.strftime("%A") if (date - today).abs < 7

    date.strftime("%b %-d")
  end

  def food_allergen_note(food)
    return if food.allergens.empty?

    "Contains #{food.allergen_labels.to_sentence.downcase} — check the packet"
  end
end
