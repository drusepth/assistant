module Pets
  # The vet field is a name you type, not a contact you had to go and make
  # first. The vet is still an ordinary contact — callable from the pet's
  # page, attachable to the appointment, what intake matches a vet sheet
  # against — so a new name becomes one, quietly: in the Address Book, not
  # the circle, which only holds people flagged keep_in_touch.
  #
  # A name you already have links that contact rather than making a twin.
  # This is a lookup of what the user typed against names they already
  # filed, not a guess at what anything is (D-no-keyword-logic): exact,
  # case-insensitive, the user's own contact ahead of one shared with them.
  class VetContact
    def self.resolve(user, name:, phone:)
      name = name.to_s.squish
      return nil if name.blank?

      phone = phone.to_s.squish.presence
      matches = Person.visible_to(user).where("LOWER(people.name) = ?", name.downcase).order(:id).to_a
      person = matches.find { |match| match.user_id == user.id } || matches.first

      if person.nil?
        user.people.create!(name: name, phone: phone, relationship: "Vet")
      else
        # The phone box shows this contact's number, so changing it there
        # changes it on the contact — but only on the user's own; a contact
        # someone shared is theirs to edit.
        person.update!(phone: phone) if phone && person.user_id == user.id && person.phone != PhoneNumber.normalize(phone)
        person
      end
    end
  end
end
