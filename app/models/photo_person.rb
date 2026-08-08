# A manual "who's in this photo" link to the People primitive (D30) — no
# face recognition, the Q8 lesson: guessed identities cost trust. The tag
# names, it never grants: viewers of a shared photo see only the tagged
# people they could already see.
class PhotoPerson < ApplicationRecord
  belongs_to :photo
  belongs_to :person

  validates :person_id, uniqueness: { scope: :photo_id }
  validate :owner_can_see_person

  private
    def owner_can_see_person
      return if photo.nil? || person.nil?

      errors.add(:person, "must be visible to you") unless person.visible_to?(photo.user)
    end
end
