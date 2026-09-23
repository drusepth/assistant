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

  def food_allergen_note(food)
    return if food.allergens.empty?

    "Contains #{food.allergen_labels.to_sentence.downcase} — check the packet"
  end
end
