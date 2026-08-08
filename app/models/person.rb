# A contact and what matters about them. Distinct from User (a login):
# a household member usually exists as both, connected via linked_user (D8).
class Person < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizePersonJob

  belongs_to :linked_user, class_name: "User", optional: true

  validates :name, presence: true

  # The circle (D38): relationships the user is tending, marked explicitly —
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
