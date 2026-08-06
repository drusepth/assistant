# The Tools mode (D19): a Tool is a first-party pipeline — gather owned
# context, make one or a few LLM calls, land the result as draft primitives.
# Tools are code, not data (they're behavior, unlike the D12 taxonomy), and
# this explicit slug list is the whole registry: first-party only (D11).
module Tool
  SLUGS = %w[
    decode_letter dispute_letter insurance_appeal debt_collector_response
    deposit_demand results_explainer doctor_visit_prep negotiation_prep
    benefits_screener learn_something tutor
    cancel_subscription reconnect moving
    start_a_hobby what_should_i_make_next find_your_people
  ].freeze

  module_function

  def all = SLUGS.map { |slug| find(slug) }

  def find(slug)
    const_get(slug.to_s.camelize) if SLUGS.include?(slug.to_s)
  end

  def find!(slug)
    find(slug) || raise(ActiveRecord::RecordNotFound, "no tool named #{slug.inspect}")
  end

  # Tools flow both ways along the taxonomy: one registered on a subsection
  # (rights → disputes) shows on the parent page too, and one registered on
  # a parent (hobbies) shows on every subsection page — user-created hobby
  # lenses (D25) can't be registered on ahead of time, so the Hobbies tools
  # belong on each hobby's page.
  def for_section(section)
    slugs = [ section.slug, section.parent&.slug, *section.children.map(&:slug) ].compact
    all.select { |tool| tool.section_slugs.intersect?(slugs) }
  end
end
