class AddStapleToFoods < ActiveRecord::Migration[8.1]
  def change
    # "We always have it" — water, salt, oil. A staple counts as in the
    # kitchen without a row, so a recipe isn't forever one "water" short of
    # ready. The model proposes it when filing; the household decides.
    add_column :foods, :staple, :boolean, null: false, default: false
  end
end
