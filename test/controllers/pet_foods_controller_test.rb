require "test_helper"

class PetFoodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @rex = create_pet
  end

  def add(**overrides)
    post pet_foods_path(@rex), params: { pet_food: {
      name: "Adult chicken", brand: "Acme", form: "dry", amount_per_day: "300", unit: "g",
      package_amount: "12000", package_cost: "54.00", opened_on: Date.current.iso8601,
      started_on: Date.current.iso8601
    }.merge(overrides) }
  end

  test "a price typed in currency lands as cents" do
    add
    assert_equal 5_400, @rex.pet_foods.sole.package_cost_cents
  end

  test "replacing a food ends the old one instead of losing it" do
    add
    old = @rex.pet_foods.sole
    post pet_foods_path(@rex), params: {
      pet_food: { name: "Senior lamb", form: "dry", unit: "g", started_on: Date.current.iso8601 },
      replaces_current: "1"
    }

    assert_equal Date.current, old.reload.ended_on
    assert_equal "Senior lamb", @rex.pet_foods.current.sole.name
    assert_equal 2, @rex.pet_foods.count, "the history is the point"
  end

  test "reorder puts one all-day event on the calendar, excluded from the radar" do
    add(opened_on: 30.days.ago.to_date.iso8601)
    food = @rex.pet_foods.sole

    assert_difference -> { users(:one).events.count }, 1 do
      post reorder_pet_food_path(@rex, food)
    end

    event = users(:one).events.order(:id).last
    assert_equal "Reorder Rex's Acme Adult chicken", event.title
    assert event.all_day?
    assert_equal Health::CareRadar::EXCLUDED, event.care_kind, "a reorder is not a visit"
    assert_equal food.runs_out_on, event.starts_at.to_date
    assert_includes event.sections, @rex.section

    assert_no_difference -> { users(:one).events.count } do
      post reorder_pet_food_path(@rex, food)
    end
  end

  test "a food with no reorder date is refused rather than guessed at" do
    add(opened_on: "")
    assert_no_difference -> { users(:one).events.count } do
      post reorder_pet_food_path(@rex, @rex.pet_foods.sole)
    end
    assert_equal "That food doesn't carry enough numbers to work out a reorder date.", flash[:alert]
  end

  test "ending a food moves it to the history and deletes nothing" do
    add
    food = @rex.pet_foods.sole
    patch end_food_pet_food_path(@rex, food)

    assert_equal Date.current, food.reload.ended_on
    assert PetFood.exists?(food.id)
  end

  test "the shelf is the owner's — a shared viewer can read but not feed" do
    users(:one).granted_access_grants.create!(grantee: users(:two), subject: @rex)
    sign_in_as users(:two)

    post pet_foods_path(@rex), params: { pet_food: { name: "Whatever", form: "dry", unit: "g", started_on: Date.current.iso8601 } }
    assert_response :not_found
    assert_empty @rex.pet_foods
  end

  test "the next bag goes on the kitchen's shopping list, saying who it's for" do
    add

    post add_to_list_pet_food_path(@rex, @rex.pet_foods.sole)

    kitchen = Kitchens::Current.for(users(:one))
    line = ShoppingList.default_for(kitchen).items.sole
    assert_equal [ "Acme Adult chicken", "for #{@rex.name}" ], [ line.item, line.note ]
  end
end
