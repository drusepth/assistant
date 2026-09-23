# One vaccine dose a pet was given — or one titer drawn or vet exemption
# issued in place of a dose (D-pet-vaccinations). The visit it happened at is
# an Event, which is dated and on the calendar; what was *given* at it has
# its own fields and its own clock per item, so it is a row of its own.
#
# One row per dose rather than one per vaccine, because the history is the
# record: the vet asks when the first FVRCP was, a recall names a lot, a
# reaction belongs to a particular shot. "What is current" is a query over
# the latest dose per vaccine (Pets::VaccineStatus), never a column someone
# has to keep right.
#
# `due_on` is "good until / next dose due". It comes from the certificate, or
# from the duration the owner picked — never from a guess (see Pets::Vaccines
# for why). A duration means the date is derived from it; a typed date is the
# certificate's and the controller clears the duration when one is typed.
#
# Visible exactly when the pet is: there are no grants of its own, and a
# household member the pet is shared with reads the record and can log a
# dose (`user_id` says who did).
class PetVaccination < ApplicationRecord
  KINDS = %w[ dose titer exemption ].freeze
  KIND_LABELS = { "dose" => "Vaccination", "titer" => "Titer test", "exemption" => "Vet exemption" }.freeze

  # The group a vaccine with no catalog key is recognised by: its printed name,
  # compared exactly after folding case and spacing. String equality, not
  # classification — two different spellings stay two rows until the owner
  # picks the catalog entry for one of them.
  NAME_GROUP_PREFIX = "name:".freeze

  belongs_to :pet
  # Who logged it, while they are still in the household — a member who
  # leaves takes nothing of the pet's history with them.
  belongs_to :user, optional: true
  belongs_to :vet, class_name: "Person", optional: true
  belongs_to :document, optional: true
  belongs_to :event, optional: true

  before_validation :fill_name_from_catalog
  before_validation :derive_due_on

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, length: { maximum: 200 }
  validates :given_on, presence: true
  validates :duration_months, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 120 }, allow_nil: true
  validates :series_dose, numericality: { only_integer: true, greater_than: 0, less_than: 10 }, allow_nil: true
  validates :administered_by, :product, :lot_number, :tag_number, :site, length: { maximum: 200 }
  validates :reaction, :notes, length: { maximum: 5_000 }
  validate :given_on_not_in_the_future
  validate :due_on_after_given_on
  validate :vaccine_known_for_species

  # Through the pet, which is the only wall (D9): a shared pet's doses are
  # readable by whoever the pet is shared with, and nobody else's.
  scope :visible_to, ->(user) { where(pet_id: Pet.visible_to(user).select(:id)) }
  scope :chronological, -> { order(given_on: :desc, id: :desc) }
  scope :with_reaction, -> { where.not(reaction: [ nil, "" ]) }

  def self.group_key_for(vaccine_key, name)
    vaccine_key.presence || "#{NAME_GROUP_PREFIX}#{name.to_s.downcase.squish}"
  end

  def group_key = self.class.group_key_for(vaccine_key, name)

  def catalog_entry = vaccine_key.present? ? Pets::Vaccines.find(pet&.species, vaccine_key) : nil

  # What the vaccine is called on the card: the catalog label when it has one,
  # so "Nobivac 3-Rabies" and "Rabies 3yr" both read "Rabies" in the list and
  # keep their printed names in the history.
  def vaccine_label = catalog_entry&.label || name

  def kind_label = KIND_LABELS.fetch(kind, kind.humanize)
  def dose? = kind == "dose"
  def titer? = kind == "titer"
  def exemption? = kind == "exemption"

  def duration_phrase = duration_months && Pets::Vaccines.duration_label(duration_months)

  # Who gave it, for the history and the shareable record.
  def given_by = vet&.name || administered_by.presence

  # A certificate the viewer can open — a document keeps its own visibility,
  # so a shared viewer who can't see the scan doesn't get a link to it.
  def certificate_for(viewer)
    document if document && Document.visible_to(viewer).exists?(document.id)
  end

  private
    def fill_name_from_catalog
      self.name = catalog_entry&.label if name.blank? && catalog_entry
    end

    def derive_due_on
      self.due_on = given_on + duration_months.months if duration_months.present? && given_on.present?
    end

    # A future dose is an appointment, and appointments are Events.
    def given_on_not_in_the_future
      errors.add(:given_on, "can't be in the future — book an appointment for that") if given_on && given_on > Date.current
    end

    def due_on_after_given_on
      errors.add(:due_on, "must be after the date it was given") if due_on && given_on && due_on <= given_on
    end

    def vaccine_known_for_species
      return if vaccine_key.blank? || pet.nil?

      errors.add(:vaccine_key, "isn't a vaccine the app lists for a #{pet.species_label.downcase}") unless catalog_entry
    end
end
