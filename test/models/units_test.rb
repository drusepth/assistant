require "test_helper"

class UnitsTest < ActiveSupport::TestCase
  test "imperial shows pounds and miles, metric shows what is stored" do
    imperial = Units.for("imperial")
    metric = Units.for("metric")

    assert_equal "68.8 lb", imperial.weight_phrase(31.2)
    assert_equal "31.2 kg", metric.weight_phrase(31.2)
    assert_equal "25 mi", imperial.distance_phrase(40)
    assert_equal "40 km", metric.distance_phrase(40)
    assert_equal "under 1 mi", imperial.distance_phrase(1.2)
    assert_nil imperial.weight_phrase(nil)
  end

  test "what a form posts converts back to the stored unit, and a round trip never moves the number" do
    imperial = Units.for("imperial")

    assert_equal BigDecimal("22.68"), imperial.kg_from("50")
    assert_nil imperial.kg_from("")
    assert_equal 40, imperial.km_from("25")

    (1..400).step(0.1).each do |pounds|
      shown = BigDecimal(pounds.round(1).to_s)
      assert_equal shown, imperial.weight(imperial.kg_from(shown)), "#{shown} lb drifted"
    end
    imperial.distance_range(Place::RADIUS_RANGE).each do |miles|
      assert_equal miles, imperial.distance(imperial.km_from(miles)).round, "#{miles} mi drifted"
    end
  end

  test "a radius range becomes the whole miles that land inside it" do
    range = Units.for("imperial").distance_range(Place::RADIUS_RANGE)

    assert_equal 4..186, range
    assert_includes Place::RADIUS_RANGE, Units.for("imperial").km_from(range.min)
    assert_includes Place::RADIUS_RANGE, Units.for("imperial").km_from(range.max)
  end

  test "an unknown system falls back to the default rather than raising" do
    assert_equal "imperial", Units.for("furlongs").system
    assert_equal "imperial", User.new.measurement_system
  end
end
