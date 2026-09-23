module Ui
  # "Put a person here" as one field (D-person-picker): type a few letters,
  # pick a face from what comes back, or keep typing and add someone new.
  # It replaced a <select> of the whole address book in every place that
  # adds a person — unusable the day a real address book is imported.
  #
  # Renders the field only — the caller's form owns the action and the
  # submit button. It posts `person_id` when a suggestion was picked and
  # `name` always, so the receiving controller hands both to
  # People::Picker#resolve. Without JavaScript it is a plain name field and
  # the server does the matching (an exact name is reused, never
  # duplicated).
  #
  # `place:` is where the person is going — :circle, :group (with
  # `section:`) or :photo (with `photo:`) — and decides who's suggested.
  class PersonPickerComponent < ApplicationComponent
    # `inline: true` adds the flag the circle and membership endpoints read
    # as "answer in place" (Turbo Streams, cursor kept) rather than a
    # redirect — only the forms whose page has the targets set it.
    def initialize(place:, label:, section: nil, photo: nil, placeholder: "Type a name…", input_class: nil,
                   autofocus: false, inline: false)
      @place = place
      @label = label
      @section = section
      @photo = photo
      @placeholder = placeholder
      @input_class = input_class
      @autofocus = autofocus
      @inline = inline
    end

    attr_reader :label, :placeholder, :autofocus, :inline

    def matches_url
      helpers.people_matches_path(for: @place, section_id: @section&.id, photo_id: @photo&.id)
    end

    def list_id = @list_id ||= "person-picker-#{SecureRandom.hex(4)}"

    def input_classes = [ "input", @input_class ].compact.join(" ")
  end
end
