# Display vocabulary for the mastery state machine (D-mastery-evidence).
# Sage is Education's own color: mastered takes the full step, the learning
# ladder its tints, and rusty the terracotta notch — emphasis, not error.
module EducationHelper
  MASTERY_DOT = {
    "unseen" => "border-2 border-edge bg-transparent",
    "learning" => "border-2 border-sage-400 bg-sage-100",
    "practicing" => "border-2 border-sage-500 bg-sage-200",
    "mastered" => "bg-sage-500",
    "rusty" => "border-2 border-primary-500 bg-primary-200"
  }.freeze

  MASTERY_BAR = {
    "mastered" => "bg-sage-500",
    "practicing" => "bg-sage-300",
    "learning" => "bg-sage-200",
    "rusty" => "bg-primary-300"
  }.freeze

  MASTERY_LABEL = {
    "unseen" => "not started",
    "learning" => "learning",
    "practicing" => "practicing",
    "mastered" => "mastered",
    "rusty" => "rusty"
  }.freeze

  def mastery_dot(topic, classes: "")
    tag.span(class: "inline-block size-3 flex-none rounded-full #{MASTERY_DOT[topic.mastery]} #{classes}",
      title: MASTERY_LABEL[topic.mastery], aria: { label: MASTERY_LABEL[topic.mastery] })
  end

  def mastery_label(topic) = MASTERY_LABEL[topic.mastery]

  # The state-mix bar: progress is never a single percent (D-mastery-evidence)
  # — mastered, practicing, learning, and rusty each take their own segment.
  def mastery_bar(subject, classes: "")
    counts = subject.mastery_counts
    total = counts.values.sum
    return if total.zero?

    segments = MASTERY_BAR.filter_map do |state, color|
      share = counts[state.to_sym].to_i * 100.0 / total
      tag.div(class: "h-full #{color}", style: "width: #{share.round(1)}%") if share.positive?
    end
    tag.div(safe_join(segments),
      class: "flex h-2 w-full overflow-hidden rounded-full bg-canvas #{classes}",
      role: "img", aria: { label: mastery_mix_sentence(subject) })
  end

  def mastery_mix_sentence(subject)
    counts = subject.mastery_counts
    parts = []
    parts << "#{counts[:mastered]} mastered" if counts[:mastered].to_i.positive?
    parts << "#{counts[:practicing]} practicing" if counts[:practicing].to_i.positive?
    parts << "#{counts[:learning]} learning" if counts[:learning].to_i.positive?
    parts << "#{counts[:rusty]} rusty" if counts[:rusty].to_i.positive?
    remaining = counts[:unseen].to_i
    parts << "#{remaining} to go" if remaining.positive?
    parts.any? ? parts.join(" · ") : "no topics yet"
  end
end
