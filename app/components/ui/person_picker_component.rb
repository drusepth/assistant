module Ui
  # "Put a person here" as one field (D-person-picker): type a few letters,
  # pick a face from what comes back, or keep typing and add someone new.
  # It replaced a <select> of the whole address book in every place that
  # names a contact — unusable the day a real address book is imported.
  #
  # Renders the field only — the caller's form owns the action and the
  # submit button. It posts the picked person's id in `id_field` (omit it
  # with `id_field: nil` where only a name is wanted, like a pet's vet) and
  # the typed text in `name_field` always, so the receiving controller hands
  # both to People::Picker#resolve. Without JavaScript it is a plain name
  # field and the server does the matching (an exact name is reused, never
  # duplicated).
  #
  # `place:` is where the person is going — :circle, :group (with
  # `section:`), :photo (with `photo:`), or :any for a form field that can
  # name anyone the viewer can see (a tool's "Who's it for?") — and decides
  # who's suggested.
  #
  # By default picking someone submits the form: on the People page a pick
  # *is* the action. `submit_on_pick: false` is for a field in a longer
  # form, where picking just fills it in. `person:` preselects someone.
  class PersonPickerComponent < ApplicationComponent
    # `inline: true` adds the flag the circle and membership endpoints read
    # as "answer in place" (Turbo Streams, cursor kept) rather than a
    # redirect — only the forms whose page has the targets set it.
    def initialize(place:, label:, section: nil, photo: nil, placeholder: "Type a name…", input_class: nil,
                   autofocus: false, inline: false, id_field: "person_id", name_field: "name",
                   person: nil, value: nil, submit_on_pick: true, input_id: nil, required: false)
      @place = place
      @label = label
      @section = section
      @photo = photo
      @placeholder = placeholder
      @input_class = input_class
      @autofocus = autofocus
      @inline = inline
      @id_field = id_field
      @name_field = name_field
      @person = person
      @value = value
      @submit_on_pick = submit_on_pick
      @input_id = input_id
      @required = required
    end

    attr_reader :label, :placeholder, :autofocus, :inline, :id_field, :name_field, :person,
                :submit_on_pick, :input_id, :required

    def matches_url
      helpers.people_matches_path(for: @place, section_id: @section&.id, photo_id: @photo&.id)
    end

    def list_id = @list_id ||= "person-picker-#{SecureRandom.hex(4)}"

    def input_classes = [ "input", @input_class ].compact.join(" ")

    def value = person&.name || @value
  end
end
