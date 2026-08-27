require "test_helper"

# Source-level pins on the design atoms — the failures a request test can't
# see, because the page renders perfectly and only *looks* wrong.
class DesignAtomsTest < ActiveSupport::TestCase
  VIEWS = Rails.root.glob("app/{views,components}/**/*.erb")

  # `.card` deliberately carries no padding (the rows in a list card sit
  # flush against the fold), so every card has to say where its inset comes
  # from. A card that says nothing renders its text welded to the rounded
  # edge — which is exactly what a page looks like when its stylesheet 404s,
  # and is how the school shelf came to look unstyled while every class on it
  # was compiling fine.
  #
  # Three ways to say it, and one of them has to be true:
  #   - a padding utility on the card itself (`p-5` is the house inset);
  #   - `divide-y` or `.item-stack` — the two list shapes in DESIGN.md, whose
  #     rows bring their own padding by being what they are;
  #   - `.card-flush`, for anything else whose children pad themselves.
  PADDING = /\A(?:[a-z0-9:-]+:)?p[xytblrse]?-/
  SELF_PADDING = %w[ card-flush divide-y item-stack ].freeze

  test "every card says where its padding comes from" do
    offenders = class_attributes_in(VIEWS).filter_map do |path, line, classes|
      tokens = classes.split
      next unless tokens.include?("card")
      next if tokens.any? { |token| token.match?(PADDING) }
      next if tokens.any? { |token| SELF_PADDING.include?(token.sub(/\A[a-z0-9:-]+:/, "")) }

      "#{path}:#{line} — #{classes}"
    end

    assert_empty offenders, <<~MESSAGE.chomp
      These cards pad nothing, so their content sits against the rounded
      edge and the card stops reading as a card. Add the house inset (p-5),
      or — if the children already carry it — card-flush, which says so:

      #{offenders.join("\n")}
    MESSAGE
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
