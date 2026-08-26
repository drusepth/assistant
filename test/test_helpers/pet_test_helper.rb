# A pet and her lens are created together (D-pet-primitive), so tests make
# them together too. Deliberately *not* a fixture: fixtures load for every
# test in the suite, and a stray custom section under People would change the
# world for tests about groups, lenses and the People page that have nothing
# to do with pets.
module PetTestHelper
  def create_pet(user: users(:one), name: "Rex", species: "dog", **attributes)
    user.pets.create!(
      name: name, species: species,
      section: Pets::Lens.create!(name), **attributes
    )
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include PetTestHelper
end
