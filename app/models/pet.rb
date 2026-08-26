# A member of the household who can't log in (D-pet-primitive). A pet is a
# *whom*, not a *what*: filing her care under a "Pets" section would pull the
# vet appointment off the care radar and the kibble out of the budget, which
# is the standalone failure the lens model exists to avoid. So the vet visit
# is tagged `Health + Rex` and both pages are right.
#
# The lens is the load-bearing half. Every pet owns a custom child section of
# People (Pets::Lens), which is what makes "about Rex" an ordinary tag: every
# form's section picker can already file to her, `in_section` gathers every
# primitive at once including Photos, and per-pet sharing is an ordinary
# section grant. That is also why pets never forced Q17 — a lens answers
# "which pet" without a link table or link UI on six forms.
#
# Not a Person with a species column: Person is a *contact* (email, phone,
# keep_in_touch, the Address Book, the stay-in-touch watcher), and a pet filed
# there earns a nudge to reconnect with the cat.
class Pet < ApplicationRecord
  include Visible
  include Sectionable
  # Her face on every card, through the same component and the same square
  # variant as a household member's (D-user-avatars).
  include Avatarable

  # The kind registries key off these (D-pet-care-radar). "Other" is a real
  # answer, not a fallback: we know a dog's cadence and we don't know an
  # iguana's, and saying so beats inventing one.
  SPECIES = %w[ dog cat rabbit bird reptile fish horse other ].freeze
  SPECIES_LABELS = {
    "dog" => "Dog", "cat" => "Cat", "rabbit" => "Rabbit", "bird" => "Bird",
    "reptile" => "Reptile", "fish" => "Fish", "horse" => "Horse", "other" => "Other"
  }.freeze

  belongs_to :section
  # The vet is an ordinary contact, so she's in the Address Book, callable,
  # and attachable to the appointment — "find a vet" is find_care with the
  # specialty prefilled rather than a tool of its own.
  belongs_to :vet, class_name: "Person", optional: true

  validates :name, presence: true
  validates :species, inclusion: { in: SPECIES }
  validates :weight_kg, numericality: { greater_than: 0, less_than: 2_000 }, allow_nil: true

  # Present tense first, then the ones who are remembered — the People page
  # renders them as two strips and every radar and watcher reads `active`.
  scope :active, -> { where(died_on: nil, left_on: nil).order(:name) }
  scope :gone, -> { where.not(died_on: nil).or(where.not(left_on: nil)).order(:name) }

  # Ui::AvatarComponent asks its subject whether it has a household account
  # (D8), because a contact can borrow its linked member's face. A pet never
  # has one, and says so rather than making the component learn about pets.
  def linked_user = nil

  def active? = died_on.nil? && left_on.nil?
  def died? = died_on.present?
  def species_label = SPECIES_LABELS.fetch(species, "Other")

  # Everything tagged with her lens, for any primitive — the whole point of
  # D-pet-primitive in one method. Reads through visible_to, so a household
  # member sees exactly what was shared with them.
  def items(model, viewer)
    model.visible_to(viewer).in_section(section)
  end

  # "4 years old" / "about 4 years old" / nil. A rescue's date of birth is a
  # vet's guess, and printing a precise birthday for a guessed date is a
  # small lie the app tells on every page.
  def age_phrase(on: Date.current)
    return nil unless born_on

    years = ((on - born_on) / 365.25).floor
    phrase = years.zero? ? "#{((on - born_on) / 30.44).floor} months old" : "#{years} #{"year".pluralize(years)} old"
    born_on_estimated ? "about #{phrase}" : phrase
  end

  # What the header says under her name: "Dog · Golden retriever · 4 years old".
  def descriptor
    [ species_label, breed.presence, age_phrase ].compact.join(" · ")
  end

  # A birthday the app can honestly celebrate: a known date of birth, else
  # the adoption date (the "gotcha day" a rescue household actually keeps).
  def celebration
    return [ born_on, "Birthday" ] if born_on && !born_on_estimated
    return [ adopted_on, "Gotcha day" ] if adopted_on

    nil
  end
end
