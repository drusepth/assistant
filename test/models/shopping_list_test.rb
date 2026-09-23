require "test_helper"

class ShoppingListTest < ActiveSupport::TestCase
  setup do
    @kitchen = users(:one).kitchens.create!(name: "Home")
    @list = ShoppingList.default_for(@kitchen)
  end

  test "lines parse like recipe ingredients and skip dividers" do
    @list.add_lines("2 tins chickpeas\nFor the sauce:\nmilk, the big one", by: users(:one))

    items = @list.items.to_a
    assert_equal [ "2 cans chickpeas", "milk" ], items.map(&:display)
    assert_equal "the big one", items.last.note
    assert_equal users(:one), items.first.added_by
  end

  test "the same item in the same unit adds up; a different unit stays its own line" do
    @list.add_lines("1 onion\n200 g flour", by: users(:one))
    @list.add_lines("2 onions\n1 cup flour\nonions", by: users(:two))

    assert_equal [ "3 onions", "200 g flour", "1 cup flour" ], @list.items.reload.map(&:display)
  end

  test "an amount fills in a line that had none" do
    @list.add_lines("lemons", by: users(:one))
    @list.add_lines("3 lemons", by: users(:one))

    assert_equal [ "3 lemons" ], @list.items.reload.map(&:display)
  end

  test "checked lines stay in the basket for the day, then only in history" do
    item = @list.add_lines("milk", by: users(:one)).first
    item.check!(by: users(:two))

    assert_equal [ item ], @list.basket_items.to_a
    assert_empty @list.open_items

    travel 1.day do
      assert_empty @list.basket_items
    end
    travel 31.days do
      ShoppingList.sweep_history
      assert_not ShoppingListItem.exists?(item.id)
    end
  end

  test "a checked line doesn't absorb a new one" do
    @list.add_lines("2 onions", by: users(:one)).first.check!(by: users(:one))
    @list.add_lines("1 onion", by: users(:one))

    assert_equal 1, @list.open_items.count
  end
end
