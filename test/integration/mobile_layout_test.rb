require "test_helper"

# The phone-width guard. A CSS grid with no column definition at the base
# breakpoint gets a single *implicit* column, and an implicit column is
# `auto` — which sizes to its widest child instead of to the page. One card
# holding a long task title then pushes the whole document wider than the
# viewport, and every page on the phone scrolls sideways. `grid-cols-1`
# compiles to `repeat(1, minmax(0, 1fr))`, which is the fix: the track can
# no longer grow past its share of the page, so `truncate` inside it works.
#
# This is a source-level check rather than a rendered one: the failure is a
# layout fact no request test can see, and the rule is cheap to state.
class MobileLayoutTest < ActiveSupport::TestCase
  VIEWS = Rails.root.glob("app/{views,components}/**/*.erb")

  # Mobile Safari zooms the page in when a field under 16px takes focus, and
  # does not zoom back out. It is invisible on a desktop and ruinous on an
  # iPhone, which is exactly the kind of regression a pin is for. Source-level
  # again: the rule lives in the stylesheet, and nothing rendered can see it.
  test "fields are at least 16px on a touch device, or iOS zooms and stays zoomed" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    rule = css[/@media \(pointer: coarse\)\s*\{(.+?)\n\}/m, 1]

    assert rule, "no (pointer: coarse) block in application.css — the iOS zoom fix is gone"
    assert_match(/\.input\b/, rule, "`.input` no longer gets its touch font size")
    assert_match(/\.composer-input\b/, rule, "`.composer-input` no longer gets its touch font size")
    assert_match(/font-size:\s*(1rem|16px)/, rule, "the touch font size is below 16px again")
  end

  test "every grid names its base column count" do
    offenders = class_attributes_in(VIEWS).filter_map do |path, line, classes|
      tokens = classes.split
      next unless tokens.include?("grid")
      next if tokens.any? { |token| token.start_with?("grid-cols-") }

      "#{path}:#{line} — #{classes}"
    end

    assert_empty offenders, <<~MESSAGE.chomp
      These grids have no base grid-cols-* class, so on a phone they lay out
      in one implicit `auto` column that sizes to its widest child and pushes
      the page sideways. Add grid-cols-1 (the responsive variants stay):

      #{offenders.join("\n")}
    MESSAGE
  end

  # The other half of the same story: a pill whose label cannot wrap is a pill
  # that can be wider than the phone holding it.
  test "the button atom lets a long label wrap" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    button_rule = css[/\.btn \{(.+?)\}/m, 1]

    assert_not_includes button_rule.to_s, "whitespace-nowrap",
      "A .btn with whitespace-nowrap overflows its container on a narrow screen."
    assert_includes button_rule.to_s, "max-w-full",
      "A .btn must never be wider than what holds it."
  end

  private
    def class_attributes_in(paths)
      paths.flat_map do |path|
        relative = path.relative_path_from(Rails.root)
        path.readlines.flat_map.with_index(1) do |line, number|
          line.scan(/class="([^"]*)"/).map { |(classes)| [ relative, number, classes ] }
        end
      end
    end
end
