require "test_helper"

# The pronoun reaches the model or it doesn't reach the user (D-pronouns).
# Every one of these tools writes prose *about* someone and hands it back for
# the user to send; a model left to infer a pronoun from a name will guess,
# and the guess lands in a draft addressed to that person.
class PronounContextTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  def run_for(slug, **inputs)
    @user.tool_runs.create!(tool_slug: slug, inputs: inputs.transform_keys(&:to_s), status: :queued)
  end

  test "every people tool that describes a contact tells the model what to call them" do
    rosa = @user.people.create!(name: "Rosa Iyer", pronoun: "she")

    reconnect = Tool::Reconnect.new(run_for("reconnect", person_id: rosa.id)).send(:user_prompt)
    assert_match "Refer to them as: she/her/her", reconnect

    gift = Tool::GiftIdeas.new(run_for("gift_ideas", person_id: rosa.id)).send(:user_prompt)
    assert_match "Refer to them as: she/her/her", gift
  end

  test "a contact with nothing recorded is described as they, never left blank" do
    sam = @user.people.create!(name: "Sam Pryor")
    prompt = Tool::Reconnect.new(run_for("reconnect", person_id: sam.id)).send(:user_prompt)

    assert_match "Refer to them as: they/them/their", prompt,
      "an absent line lets the model fall back on the name; this one doesn't"
  end

  test "the pet sheet carries the pet's pronoun, and an owner's override beats the sex" do
    rex = create_pet(user: @user, sex: "male")
    assert_match "Refer to this pet as: he/him/his",
      Tool::VetVisitPrep.new(run_for("vet_visit_prep", pet_id: rex.id)).send(:user_prompt)

    rex.update!(pronoun: "they")
    assert_match "Refer to this pet as: they/them/their",
      Tool::LostPet.new(run_for("lost_pet", pet_id: rex.id)).send(:user_prompt),
      "the app does not argue with an owner about their own animal"
  end

  # A worked example in a prompt is an instruction: gift_ideas used to show
  # the model "[ask her sister] which authors she's into lately", which would
  # have out-argued any pronoun the record supplied.
  test "no people prompt teaches a gendered example the record would then contradict" do
    gendered = /\b(she|her|hers|he|him|his|himself|herself)\b/i

    [ Tool::GiftIdeas, Tool::Reconnect, Tool::Bereavement, Tool::EmailFollowUp, Tool::WhatDoISay ].each do |tool|
      name = %i[ SYSTEM_PROMPT BEHAVIOR BRIEF ].find { |const| tool.const_defined?(const, false) }
      assert name, "#{tool} has no prompt constant this test knows how to read"
      assert_no_match gendered, tool.const_get(name), "#{tool}::#{name} instructs the model in gendered terms"
    end
  end
end
