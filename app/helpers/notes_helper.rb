module NotesHelper
  def note_auto_sort_hint
    if auto_sort_enabled?
      "Just jot it down — your assistant titles it and files it into sections."
    else
      "A title and sections can be added after saving, from the note's edit page."
    end
  end
end
