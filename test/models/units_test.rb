require "test_helper"

class UnitsTest < ActiveSupport::TestCase
  test "pounds and miles are what is stored, so imperial is only formatting" do
    imperial = Units.for("imperial")

    assert_equal "68.8 lb", imperial.weight_phrase(68.8)
    assert_equal "25 mi", imperial.distance_phrase(25)
    assert_equal "under 1 mi", imperial.distance_phrase(0.4)
    assert_equal BigDecimal("50"), imperial.lb_from("50")
    assert_equal 25, imperial.mi_from("25")
    assert_nil imperial.weight_phrase(nil)
    assert_nil imperial.lb_from("")
  end

  test "metric is the exception: converted for display and back on the way in" do
    metric = Units.for("metric")

    assert_equal "31.21 kg", metric.weight_phrase(68.8)
    assert_equal "40 km", metric.distance_phrase(25)
    assert_equal BigDecimal("67.24"), metric.lb_from("30.5")
    assert_equal 25, metric.mi_from("40")
  end

  test "a metric weight survives a round trip through the pound column" do
    metric = Units.for("metric")

    (1..200).step(0.01).first(2_000).each do |kilos|
      shown = BigDecimal(kilos.round(2).to_s)
      assert_equal shown, metric.weight(metric.lb_from(shown)), "#{shown} kg drifted"
    end
  end

  test "a radius range becomes the whole numbers of the reader's unit that land inside it" do
    assert_equal Place::RADIUS_RANGE, Units.for("imperial").distance_range(Place::RADIUS_RANGE)

    metric = Units.for("metric")
    range = metric.distance_range(Place::RADIUS_RANGE)
    assert_includes Place::RADIUS_RANGE, metric.mi_from(range.min)
    assert_includes Place::RADIUS_RANGE, metric.mi_from(range.max)
  end

  test "an unknown system falls back to imperial rather than raising" do
    assert_equal "imperial", Units.for("furlongs").system
    assert_equal "imperial", User.new.measurement_system
  end
end
