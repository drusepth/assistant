# A member of the household who can't log in (D-pet-primitive). A pet is a
# *whom*, not a *what*: filing their care under a "Pets" section would pull the
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
  include Pronounced
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

  # A closed set, because the app's own copy reads it to pick a pronoun
  # (D-pronouns) and free text can't be read that way. Blank is the
  # default and a real answer — a stray cat's sex is often nobody's to know —
  # and it yields "they". Spayed/neutered is a status rather than a sex, so it
  # is its own flag; the lost-pet poster and the insurance tool want it apart.
  SEXES = %w[ female male ].freeze
  SEX_LABELS = { "female" => "Female", "male" => "Male" }.freeze

  # The pronoun a recorded sex implies, which is the whole reason the set
  # above is closed. A household that disagrees sets `pronoun` and this stops
  # being consulted — the escape hatch costs one nullable column and means
  # the app never argues with an owner about their own animal.
  SEX_PRONOUNS = { "female" => "she", "male" => "he" }.freeze

  belongs_to :section
  # The vet is an ordinary contact, so she's in the Address Book, callable,
  # and attachable to the appointment — "find a vet" is find_care with the
  # specialty prefilled rather than a tool of its own.
  belongs_to :vet, class_name: "Person", optional: true

  # What she eats, and what she ate (D-pet-food-shelf).
  has_many :pet_foods, dependent: :destroy

  # Her lens goes with her, by whatever path she goes: the controller, a
  # removed household member cascading through `users.pets`, or the console.
  # Doing this in the controller left an empty "Rex" section under People
  # every time a member was removed. Tagged items survive and keep their
  # other tags — the section_taggings go with the section, as for any lens.
  after_destroy { section&.destroy }

  validates :name, presence: true
  validates :species, inclusion: { in: SPECIES }
  validates :sex, inclusion: { in: SEXES }, allow_blank: true
  validates :weight_lb, numericality: { greater_than: 0, less_than: 4_400 }, allow_nil: true

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

  # "Female" / "Neutered male" / nil — the one line the details list, the
  # poster and the vet-prep sheet all print.
  def sex_label
    return nil if sex.blank?

    neutered? ? "#{sex == "female" ? "Spayed" : "Neutered"} #{sex}" : SEX_LABELS[sex]
  end

  # Everything tagged with their lens, for any primitive — the whole point of
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

  private
    # A pet is the one record with a second place to look: an owner who set a
    # pronoun outright wins, and otherwise the sex on file answers it.
    def pronoun_key = pronoun.presence || SEX_PRONOUNS[sex]
end
