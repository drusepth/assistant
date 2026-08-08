module PeopleHelper
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
end
