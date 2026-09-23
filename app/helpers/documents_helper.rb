module DocumentsHelper
  def document_auto_sort_hint
    if auto_sort_enabled?
      "Your assistant reads it, summarizes it in plain language, and files it into sections."
    else
      "Configure an AI model in Settings to get summaries; a description and sections can be added after saving."
    end
  end

  # Where an insurance document shows up, as a sentence fragment of links:
  # the Health page's coverage card always, and the Papers card of every pet
  # whose lens it carries (Pets::Papers puts policies first). The Details
  # row says this instead of naming a setting, so the answer to "why is
  # this asking me about insurance?" is what the answer changes.
  def insurance_places(document)
    link = "text-primary-700 hover:underline"
    pets = Pet.visible_to(Current.user).where(section_id: document.section_ids).order(:name)
    places = [ link_to("your coverage on the Health page", section_path("health"), class: link) ]
    places += pets.map { |pet| link_to("#{pet.name}’s papers", pet, class: link) }
    *head, last = places
    return last if head.empty?

    safe_join([ safe_join(head, ", "), last ], head.size > 1 ? ", and " : " and ")
  end

  # Who gave the answer the Details row is showing, in plain words.
  def insurance_verdict_source(source, answer)
    case source
    when :owner then answer ? "You marked this as insurance." : "You said this isn’t insurance."
    when :reader then "Your assistant decided from what the document says."
    else "A guess from its title — your assistant hasn’t read it yet."
    end
  end
end
