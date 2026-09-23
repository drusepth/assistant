module PeopleHelper
  # The quiet text at the right of a person picker row (D-person-picker):
  # the relationship when there is one ("mother"). A name the results
  # repeat always gets *something* — email, then phone, then the last line
  # of the address — since two identical rows are a coin flip.
  def person_picker_hint(person, repeated: false)
    return person.relationship if person.relationship.present?
    return nil unless repeated

    person.email.presence || PhoneNumber.format(person.phone) || person.address.to_s.lines.map(&:strip).reject(&:blank?).last
  end

  def contact_recency_phrase(person)
    if person.last_contacted_on
      "Last contact #{time_ago_in_words(person.last_contacted_on)} ago"
    else
      "No contact logged yet"
    end
  end

  def birthday_phrase(person)
    date = person.next_birthday
    date == Date.current ? "today!" : "#{date.strftime("%B %-d")}, in #{distance_of_time_in_words(Date.current, date)}"
  end

  def person_auto_sort_hint
    if auto_sort_enabled?
      "Optional — your assistant files them into sections and fills in the relationship if you mention one."
    else
      "Contact details, birthday, and sections can be added after saving, from the person's edit page."
    end
  end

  # Everything the Address Book's instant filter matches a keystroke
  # against (D-address-book-directory). It rides on the row as a data
  # attribute so filtering is a string test against the DOM rather than a
  # round trip — the same fields the server searches, plus the phone as
  # printed and with its formatting stripped, because people type it both
  # ways.
  def directory_haystack(person)
    digits = person.phone.to_s.gsub(/\D/, "")
    [ person.name, person.relationship, person.email, PhoneNumber.format(person.phone), digits,
      person.address, person.notes.to_s.truncate(120),
      person.sections.reject { |section| section.slug == "people" }.map(&:name).join(" ") ]
      .compact_blank.join(" ").downcase
  end

  # "12 of 431 people" while something is filtering, plain "431 people"
  # otherwise. The number belongs beside the search box rather than in the
  # page subtitle, because it is the one thing on the page that answers
  # "did my query do anything".
  def directory_count_phrase(directory)
    roster = directory.roster_size
    shown = directory.total
    shown == roster ? pluralize(roster, "person") : "#{shown} of #{pluralize(roster, "person")}"
  end

  def directory_chip_class(active)
    "chip transition-colors #{active ? "bg-primary-100 text-primary-800" : "bg-stone-100 text-stone-700 hover:bg-stone-200"}"
  end
end
