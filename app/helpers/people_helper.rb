module PeopleHelper
  def person_auto_sort_hint
    if auto_sort_enabled?
      "Optional — your assistant files them into sections and fills in the relationship if you mention one."
    else
      "Contact details, birthday, and sections can be added after saving, from the person's edit page."
    end
  end
end
