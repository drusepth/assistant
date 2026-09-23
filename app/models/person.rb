# A contact and what matters about them. Distinct from User (a login):
# a household member usually exists as both, connected via linked_user (D8).
class Person < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable
  # A face for every contact, not only the ones with a household login
  # (D-contact-photos): same attachment and same square variant as a member's.
  include Avatarable
  # How the app refers to this contact in its own copy, and how it tells a
  # model to refer to them (D-pronouns). Blank means "they" — a contact
  # record has no business guessing, and nothing here asks for anyone's sex.
  include Pronounced

  AUTO_SORT_JOB = CategorizePersonJob

  belongs_to :linked_user, class_name: "User", optional: true

  has_many :photo_people, dependent: :destroy
  has_many :photos, through: :photo_people

  # Pets who see this contact (D-pet-primitive). Nullify, not restrict:
  # removing the vet from your address book is not a claim about the dog, and
  # without this the delete died on a foreign key.
  has_many :patients, class_name: "Pet", foreign_key: :vet_id,
    inverse_of: :vet, dependent: :nullify

  # Typed through the mask, imported from a vCard, or picked off the phone's
  # contacts, it lands in one shape (PhoneNumber).
  normalizes :phone, with: ->(phone) { PhoneNumber.normalize(phone) }

  validates :name, presence: true

  # The circle (D-people-dashboard): relationships the user is tending, marked explicitly —
  # an import must not turn 300 contacts into 300 obligations. The flag is
  # intent; last_contacted_on (Q8) stays the only recency signal.
  scope :circle, -> { where(keep_in_touch: true) }
  # Oldest logged contact first; never-logged last (their staleness is
  # unknown, not maximal).
  scope :stalest_first, -> { order(Arel.sql("people.last_contacted_on IS NULL, people.last_contacted_on ASC, people.name ASC")) }

  # Next-occurrence birthday math lives here once, shared by the section
  # page's Coming up strip and the birthday-radar watcher. Ruby, not SQL:
  # year wrap and Feb 29 make month/day comparison hairy in SQLite, and the
  # circle is small.
  def self.birthday_within(days, from: Date.current)
    where.not(birthday: nil)
      .select { |person| person.next_birthday(from: from) <= from + days }
      .sort_by { |person| person.next_birthday(from: from) }
  end

  def next_birthday(from: Date.current)
    return nil unless birthday

    this_year = birthday_in_year(from.year)
    this_year < from ? birthday_in_year(from.year + 1) : this_year
  end

  private
    # Feb 29 birthdays fall on Feb 28 in common years.
    def birthday_in_year(year)
      Date.new(year, birthday.month, birthday.day)
    rescue Date::Error
      Date.new(year, birthday.month, birthday.day - 1)
    end
end
