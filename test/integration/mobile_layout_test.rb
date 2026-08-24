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
  LAYOUT = Rails.root.join("app/views/layouts/application.html.erb")

  # Mobile Safari zooms the page in when a field under 16px takes focus, and
  # does not zoom back out. It is invisible on a desktop and ruinous on an
  # iPhone, which is exactly the kind of regression a pin is for. Source-level
  # again: the rule lives in the stylesheet, and nothing rendered can see it.
  test "fields are at least 16px on a touch device, or iOS zooms and stays zoomed" do
    blocks = coarse_pointer_blocks(Rails.root.join("app/assets/tailwind/application.css").read)
    assert blocks.any?, "no (pointer: coarse) block in application.css — the iOS zoom fix is gone"

    %w[ .input .composer-input ].each do |selector|
      rule = blocks.find { |block| block.match?(/#{Regexp.escape(selector)}[\s,{]/) }

      assert rule, "`#{selector}` no longer gets a touch font size — iOS will zoom on it and stay zoomed"
      assert_match(/font-size:\s*(1rem|1[6-9]px|[2-9]\d px)/x, rule,
        "`#{selector}`'s touch font size dropped below 16px again")
    end
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

  # Reach, not just fit. The nav drawer's only opener used to be the header
  # hamburger, pinned to the top of a page that is ~900 points tall on a
  # phone — the one corner the hand holding it cannot get to. The swipe
  # gesture can't be the answer on its own (both mobile browsers eat the
  # left-edge drag for their back gesture, and an invisible gesture is no
  # affordance at all), so the layout must keep a *bottom*-anchored toggle.
  test "the phone layout carries a nav toggle within thumb reach" do
    layout = LAYOUT.read
    toggles = layout.scan(/<button\b[^>]*nav#toggle[^>]*>/)

    assert toggles.any? { |button| button.include?("fixed") && button.match?(/\bbottom-/) },
      "The drawer needs an opener anchored to the bottom of the viewport, not " \
      "only the one in the sticky header. Found: #{toggles.size} nav#toggle button(s), " \
      "none of them bottom-anchored."
  end

  # A fixed control at the foot of the screen lands under the iPhone home
  # indicator unless it is pushed up by the inset.
  test "the thumb-reach toggle clears the home indicator" do
    assert_includes LAYOUT.read, "env(safe-area-inset-bottom)",
      "A bottom-anchored control needs safe-area-inset-bottom in its offset, " \
      "or it sits under the home indicator on a notched phone."
  end

  private
    # Every `@media (pointer: coarse)` block in the sheet, brace-matched.
    # There is more than one of them now (the chat has its own), so finding
    # "the" block with a regex quietly checks the wrong one.
    def coarse_pointer_blocks(css)
      css.enum_for(:scan, /@media \(pointer: coarse\)\s*\{/).map { Regexp.last_match.end(0) }.map do |start|
        depth = 1
        index = start
        while depth.positive? && index < css.length
          depth += 1 if css[index] == "{"
          depth -= 1 if css[index] == "}"
          index += 1
        end
        css[start...(index - 1)]
      end
    end

    def class_attributes_in(paths)
      paths.flat_map do |path|
        relative = path.relative_path_from(Rails.root)
        path.readlines.flat_map.with_index(1) do |line, number|
          line.scan(/class="([^"]*)"/).map { |(classes)| [ relative, number, classes ] }
        end
      end
    end
end
