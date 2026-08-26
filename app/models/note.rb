class Note < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizeNoteJob

  # A structured flavor of note. "medication" is the first (docs/HEALTH.md
  # §7): the med list is notes, so it exports, shares, and feeds tool context
  # like everything else. "allergy" is the second (§8), on the same terms.
  # The plain case is named rather than left NULL (D-flavor-columns-not-null),
  # so negated queries like except_allergies below mean what they say.
  PLAIN = "plain".freeze
  MEDICATION = "medication".freeze
  ALLERGY = "allergy".freeze
  KINDS = [ PLAIN, MEDICATION, ALLERGY ].freeze

  scope :plain, -> { where(kind: PLAIN) }
  scope :medications, -> { where(kind: MEDICATION) }
  scope :allergies, -> { where(kind: ALLERGY) }
  scope :except_allergies, -> { where.not(kind: ALLERGY) }

  # Allergy severity, worst first — the order the card and the prep sheet
  # list them in, because that is the order they matter in.
  SEVERITIES = %w[ severe moderate mild ].freeze

  validates :body, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :severity, inclusion: { in: SEVERITIES }, allow_nil: true

  def plain? = kind == PLAIN
  def medication? = kind == MEDICATION
  def allergy? = kind == ALLERGY
  def severe? = severity == "severe"

  # Worst-first, then alphabetical. Anything without a severity sorts last:
  # an unrated allergy is not a mild one, it's an unanswered question, and
  # the top of the list belongs to the ones that can put you in an ambulance.
  scope :by_severity, -> {
    order(Arel.sql(<<~SQL.squish), :title)
      CASE severity #{SEVERITIES.each_with_index.map { |s, i| "WHEN '#{s}' THEN #{i}" }.join(" ")} ELSE #{SEVERITIES.size} END
    SQL
  }
end
