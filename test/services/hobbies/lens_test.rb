require "test_helper"

# Hobby lenses (D25): user-created child sections of Hobbies, sharing one
# slug namespace with the seeded taxonomy.
class Hobbies::LensTest < ActiveSupport::TestCase
  test "creates a custom child of Hobbies with a parameterized slug" do
    lens = Hobbies::Lens.find_or_create!("Birdwatching")

    assert_equal sections(:hobbies), lens.parent
    assert lens.custom?
    assert_equal "birdwatching", lens.slug
    assert_equal "Birdwatching", lens.name
  end

  test "capitalizes a lowercase name and positions after existing children" do
    first = Hobbies::Lens.find_or_create!("guitar")
    second = Hobbies::Lens.find_or_create!("chess")

    assert_equal "Guitar", first.name
    assert_operator second.position, :>, first.position
  end

  test "reuses an existing lens case-insensitively instead of duplicating" do
    lens = Hobbies::Lens.find_or_create!("Guitar")

    assert_equal lens, Hobbies::Lens.find_or_create!("guitar")
    assert_equal lens, Hobbies::Lens.named("  GUITAR ")
  end

  test "a hobby named like a seeded section gets a numbered slug" do
    lens = Hobbies::Lens.find_or_create!("Budget")

    assert_equal "budget-2", lens.slug
    assert_equal sections(:hobbies), lens.parent
  end

  test "a blank name raises" do
    assert_raises(ArgumentError) { Hobbies::Lens.find_or_create!("   ") }
  end

  test "named returns nil for blank or unknown hobbies and never creates" do
    assert_nil Hobbies::Lens.named("")
    assert_no_difference "Section.count" do
      assert_nil Hobbies::Lens.named("Underwater basket weaving")
    end
  end
end
