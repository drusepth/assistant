module EventsHelper
  def event_auto_sort_hint
    if auto_sort_enabled?
      "Name it and pick a day — your assistant files it into sections and picks up any time you mention."
    else
      "Details like times, location, and sections can be added after saving, from the event's edit page."
    end
  end

  # The pet an event is about, when it is tagged with a lens the viewer can
  # see — which switches its "Counts as" picker to her kinds and offers the
  # vaccine log for a visit that has happened (D-pet-vaccinations).
  def event_pet(event)
    return @event_pets[event.id] if (@event_pets ||= {}).key?(event.id)

    @event_pets[event.id] = Pet.visible_to(Current.user).find_by(section_id: event.sections.map(&:id))
  end

  # A pet's visit counts toward *her* radar kinds, or toward her vaccine
  # record, which is a card of its own rather than a kind; everyone else's
  # picker is the Health radar's (SectionsHelper#care_kind_options).
  def event_care_kind_options(event)
    pet = event_pet(event)
    return care_kind_options(event) unless pet

    radar = Health::CareRadar.new(pet, viewer: Current.user)
    auto = radar.classify(event.title)
    options = [ [ "Auto — #{auto ? auto.label : "not routine care"}", "" ] ]
    options += radar.kinds.map { |kind| [ kind.label, kind.key ] }
    options << [ "Vaccination visit", Pets::VaccineStatus::VISIT_KIND ]
    options << [ "Not routine care", Health::CareRadar::EXCLUDED ]
    options_for_select(options, event.care_kind)
  end
end
