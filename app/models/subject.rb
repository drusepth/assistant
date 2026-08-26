# A subject someone in the household is learning (D-education-spine): the
# learner's own curriculum tree, instantiated from the curriculum commons or
# generated for any topic, never shared reference data. The spine holds
# what's known; the doing layer (Goals/Tasks/Notes) holds what's happening.
class Subject < ApplicationRecord
  include Visible
  include Sectionable

  has_many :topics, dependent: :destroy
  has_many :strands, -> { where(parent_id: nil).order(:position) }, class_name: "Topic"
  has_many :study_logs, dependent: :destroy

  enum :status, { active: 0, paused: 1, finished: 2 }, default: :active

  validates :title, presence: true

  scope :recently_studied_first, -> { order(updated_at: :desc) }

  # Mastery lives on leaves; a strand is a heading, not a thing to master.
  def leaf_topics
    topics.where.not(id: topics.select(:parent_id).where.not(parent_id: nil))
  end

  # {mastered: 9, practicing: 4, ...} over leaves — progress is always the
  # state mix, never a stored percent (D-mastery-evidence).
  def mastery_counts
    @mastery_counts ||= leaf_topics.group(:mastery).count.transform_keys(&:to_sym)
  end

  def leaf_count = mastery_counts.values.sum

  def mastered_count = mastery_counts[:mastered].to_i

  def progress_percent
    return 0 if leaf_count.zero?

    (mastered_count * 100.0 / leaf_count).round
  end

  def reload(...)
    @ordered_leaves = @mastery_counts = nil
    super
  end

  # Leaves in syllabus order: strand by strand, a childless root standing as
  # its own leaf (flat subjects are legal).
  def ordered_leaves
    @ordered_leaves ||= strands.includes(:children).flat_map do |strand|
      strand.children.any? ? strand.children.to_a : [ strand ]
    end
  end

  # The exact resume point: the leaf being worked, else the next unseen one.
  def current_topic
    ordered_leaves.find { |topic| topic.practicing? || topic.learning? } ||
      ordered_leaves.find(&:unseen?)
  end

  def rusty_topics = ordered_leaves.select(&:rusty?)

  # A generated tree is on its way: the job stamps tree_built_at even on
  # failure (the Goal pattern), so this can't stick forever. Commons and
  # hand-built subjects never show as building.
  def building_tree? = tree_built_at.nil? && topics.none? && generation_profile.present?

  def generation_profile
    profile = user.household.model_profile
    profile if profile&.configured?
  end

  def enqueue_tree_build!
    GenerateSubjectTreeJob.perform_later(self) if topics.none? && generation_profile
  end

  # Behind or ahead, honestly computed and only when the learner set a
  # target: mastered share vs. elapsed share of the runway.
  def pace
    return nil unless target_date && leaf_count.positive?

    elapsed = (Date.current - created_at.to_date).to_f
    runway = (target_date - created_at.to_date).to_f
    return nil if runway <= 0

    expected = (elapsed / runway).clamp(0.0, 1.0)
    actual = mastered_count.to_f / leaf_count
    actual >= expected ? :on_pace : :behind
  end
end
