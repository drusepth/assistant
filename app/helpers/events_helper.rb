module EventsHelper
  def event_auto_sort_hint
    if auto_sort_enabled?
      "Name it and pick a day — your assistant files it into sections and picks up any time you mention."
    else
      "Details like times, location, and sections can be added after saving, from the event's edit page."
    end
  end
end
