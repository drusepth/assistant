require "test_helper"

class Households::HeroTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @household = @user.household
  end

  test "a quiet day greets you and highlights nothing" do
    hero = Households::Hero.new(@user)

    assert_equal @household, hero.household
    assert_equal "Alice", hero.first_name
    assert_empty hero.highlights
  end

  test "the greeting follows the clock" do
    assert_equal "Good morning", hero_at("2026-08-08 08:00").greeting
    assert_equal "Good afternoon", hero_at("2026-08-08 13:00").greeting
    assert_equal "Good evening", hero_at("2026-08-08 19:00").greeting
    assert_equal "Still up", hero_at("2026-08-08 02:00").greeting
  end

  test "a circle birthday today is the first highlight" do
    @user.people.create!(name: "Mom", birthday: Date.new(1960, 8, 8), keep_in_touch: true)

    highlight = hero_on(Date.new(2026, 8, 8)).highlights.first
    assert_equal "It's Mom's birthday today", highlight.text
    assert_equal "/people/#{@user.people.last.id}", highlight.path
  end

  test "a birthday inside the week reads as a countdown" do
    @user.people.create!(name: "Dad", birthday: Date.new(1958, 8, 11), keep_in_touch: true)

    assert_equal "Dad's birthday is in 3 days", hero_on(Date.new(2026, 8, 8)).highlights.first.text
  end

  test "contacts outside the circle never reach the hero (D-people-dashboard)" do
    @user.people.create!(name: "Acquaintance", birthday: Date.new(1980, 8, 8), keep_in_touch: false)

    assert_empty hero_on(Date.new(2026, 8, 8)).highlights
  end

  test "the home anniversary shows on the day, with whole years" do
    @household.update!(moved_in_on: Date.new(2019, 8, 8))

    assert_equal "7 years in this home today", hero_on(Date.new(2026, 8, 8)).highlights.first.text
    assert_empty hero_on(Date.new(2026, 8, 9)).highlights
  end

  test "move-in day itself is not an anniversary" do
    @household.update!(moved_in_on: Date.new(2026, 8, 8))

    assert_empty hero_on(Date.new(2026, 8, 8)).highlights
  end

  test "facts summarize the household without inventing zeros" do
    assert_equal [ "2 members" ], Households::Hero.new(@user).facts

    @household.update!(region: "Texas, USA", moved_in_on: Date.new(2019, 6, 1))
    assert_equal [ "2 members", "Texas, USA", "Home since 2019" ], Households::Hero.new(@user).facts
  end

  test "at most three highlights ever show" do
    @household.update!(moved_in_on: Date.new(2019, 8, 8))
    4.times { |i| @user.people.create!(name: "Friend #{i}", birthday: Date.new(1990, 8, 8), keep_in_touch: true) }

    assert_equal 3, hero_on(Date.new(2026, 8, 8)).highlights.size
  end

  private
    def hero_on(date) = Households::Hero.new(@user, on: date, now: date.in_time_zone.change(hour: 9))
    def hero_at(time) = Households::Hero.new(@user, now: Time.zone.parse(time))
end
