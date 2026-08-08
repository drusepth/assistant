module Hobbies
  # A hobby is a lens (D25): a user-created child section of Hobbies — the
  # first user-written rows in the D12 taxonomy. The mechanism now lives in
  # Sections::Lens (generalized for People groups, D38); this module is the
  # hobbies-flavored front door the Hobbies tools and controller call.
  module Lens
    module_function

    def find_or_create!(name) = Sections::Lens.find_or_create!("hobbies", name, fallback_slug: "hobby")

    def named(name) = Sections::Lens.named("hobbies", name)
  end
end
