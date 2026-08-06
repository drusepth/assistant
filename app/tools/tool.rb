# The Tools mode (D19): a Tool is a first-party pipeline — gather owned
# context, make one or a few LLM calls, land the result as draft primitives.
# Tools are code, not data (they're behavior, unlike the D12 taxonomy), and
# this explicit slug list is the whole registry: first-party only (D11).
module Tool
  SLUGS = %w[
    decode_letter dispute_letter insurance_appeal debt_collector_response
    deposit_demand results_explainer doctor_visit_prep negotiation_prep
    learn_something
  ].freeze

  module_function

  def all = SLUGS.map { |slug| find(slug) }

  def find(slug)
    const_get(slug.to_s.camelize) if SLUGS.include?(slug.to_s)
  end

  def find!(slug)
    find(slug) || raise(ActiveRecord::RecordNotFound, "no tool named #{slug.inspect}")
  end

  # Tools registered on a section or any of its subsections — a tool living
  # on rights → disputes shows on both the Disputes and the Rights page.
  def for_section(section)
    slugs = [ section.slug, *section.children.map(&:slug) ]
    all.select { |tool| tool.section_slugs.intersect?(slugs) }
  end
end
