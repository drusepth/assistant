# A pet's sex becomes a closed set, because it is what the app's copy uses to
# decide between "she", "he" and "they" (D-pronouns) — and a free-text
# column can't answer that question. What the old placeholder invited into the
# same box ("neutered male") is the pet's *status*, not its sex, so it gets its
# own flag: the lost-pet poster and the insurance tool both want it separately.
class AddNeuteredToPets < ActiveRecord::Migration[8.1]
  def up
    add_column :pets, :neutered, :boolean, default: false, null: false

    # The only free-text values the form's own placeholder ever suggested.
    # Anything else a household typed is not a sex the app can act on, so it
    # is not guessed at — but it is not thrown away either: the original text
    # goes to `notes`, which is a field the owner reads and every pet tool
    # already sends to the model, so the fact survives where it is still
    # useful and the column ends up honest.
    known = {
      "female" => [ "female", false ], "f" => [ "female", false ],
      "male" => [ "male", false ], "m" => [ "male", false ],
      "spayed female" => [ "female", true ], "spayed" => [ "female", true ],
      "female (spayed)" => [ "female", true ],
      "neutered male" => [ "male", true ], "neutered" => [ "male", true ],
      "male (neutered)" => [ "male", true ]
    }

    Pet.reset_column_information
    Pet.where.not(sex: nil).find_each do |pet|
      typed = pet.sex.to_s.strip
      sex, neutered = known.fetch(typed.downcase, [ nil, false ])
      notes = if sex.nil? && typed.present?
        [ pet.notes.presence, "Sex, as it was typed before that field became a list: #{typed}" ].compact.join("\n\n")
      else
        pet.notes
      end

      pet.update_columns(sex: sex, neutered: neutered, notes: notes)
    end
  end

  def down
    remove_column :pets, :neutered
  end
end
