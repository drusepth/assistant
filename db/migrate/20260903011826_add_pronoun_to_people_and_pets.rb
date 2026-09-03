# One column, two records, one meaning (D-pronouns): the subject pronoun the
# app uses when it writes a sentence about someone.
#
# On `people` it is the only source — a contact record has no business asking
# for anyone's sex, and pronouns are the thing the copy actually needs.
#
# On `pets` it is an override that is normally blank, because a pet's sex is
# already on file and answers the question for nearly every household. Blank
# means "follow the sex", so the common path stays one field and the household
# that calls their male cat "they" is not told they are wrong.
class AddPronounToPeopleAndPets < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :pronoun, :string
    add_column :pets, :pronoun, :string
  end
end
