require "test_helper"

class PantryItemLandingTest < ActiveSupport::TestCase
  setup do
    @context = Landing::Context.new(user: users(:one))
    @landing = Landing::PantryItem.new(@context)
  end

  test "a receipt line lands in the viewer's kitchen, filed under Food" do
    attributes = @landing.validate("item" => "Whole milk", "quantity_note" => "2 l", "location" => "fridge", "expires_on" => "2026-10-01")

    row = @landing.land!(attributes, sections: [])

    assert_equal [ "Whole milk", "2 l", "fridge", Date.new(2026, 10, 1) ], [ row.item, row.quantity_note, row.location, row.expires_on ]
    assert_equal Kitchens::Current.for(users(:one)), row.kitchen
    assert_equal row, @landing.duplicate_of(attributes)
    assert_equal [ sections(:food) ], @landing.default_sections
  end

  test "a location outside the set is dropped, not guessed" do
    assert_nil @landing.validate("item" => "Bread", "location" => "garage")["location"]
  end
end
