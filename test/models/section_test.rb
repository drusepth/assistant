require "test_helper"

class SectionTest < ActiveSupport::TestCase
  test "top_level excludes subsections and orders by position" do
    top = Section.top_level
    assert_includes top, sections(:money)
    assert_not_includes top, sections(:budget)
    assert_equal top.sort_by(&:position), top.to_a
  end

  test "subsections belong to their parent" do
    assert_equal sections(:money), sections(:budget).parent
    assert_includes sections(:rights).children, sections(:disputes)
  end

  test "slug must be unique" do
    duplicate = Section.new(slug: "money", name: "Money Again")
    assert_not duplicate.valid?
  end

  test "seeds build the full locked taxonomy" do
    Rails.application.load_seed

    # Travel is the eighth (D-travel-facet), Pets the ninth (D-pets-section)
    # and Food the tenth (D-food-section), all added by request.
    assert_equal %w[ health hobbies education career people money rights travel pets food ],
      Section.top_level.map(&:slug)
    assert_equal %w[ budget debt taxes assets bills subscriptions benefits ],
      Section.find_by(slug: "money").children.map(&:slug)
    assert_equal %w[ immigration renting voting disputes ],
      Section.find_by(slug: "rights").children.map(&:slug)
  end
end
