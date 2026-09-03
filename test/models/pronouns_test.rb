require "test_helper"

class PronounsTest < ActiveSupport::TestCase
  test "an unrecorded pronoun is they, not a guess and not a gap" do
    [ nil, "", "  ", "xe" ].each do |key|
      assert_equal "they", Pronouns.for(key).subject, "#{key.inspect} should fall back rather than raise"
    end

    assert Pronouns.for(nil).plural?
    assert_equal "they/them/their", Pronouns.for(nil).slashed
  end

  test "the sets are complete, because copy interpolates all four forms" do
    she = Pronouns.for("she")
    assert_equal %w[ she her her herself ], [ she.subject, she.object, she.possessive, she.reflexive ]

    he = Pronouns.for("he")
    assert_equal %w[ he him his himself ], [ he.subject, he.object, he.possessive, he.reflexive ]
  end

  test "verb agreement is asked for rather than assumed" do
    assert_equal "eats", Pronouns.for("he").verb("eats", "eat")
    assert_equal "eat", Pronouns.for("they").verb("eats", "eat")
    assert_equal "she's", Pronouns.for("she").is
    assert_equal "they're", Pronouns.for("they").is
  end

  test "the picker offers exactly the stored keys, so a form can't write one we don't hold" do
    assert_equal Pronouns::KEYS, Pronouns.options.map(&:last)
    assert Pronouns.options.map(&:first).all?(&:present?)
  end
end
