module Llm
  # Shared vocabulary for prompts that file items into the section taxonomy:
  # the slug listing shown to the model, and matching its answer back to
  # Section records (unknown slugs dropped, the model's relevance order kept).
  module Taxonomy
    module_function

    def listing
      Section.order(:parent_id, :position).map { |section| "#{section.slug} — #{section.qualified_name}" }.join("\n")
    end

    def match(slugs, limit:)
      wanted = Array(slugs).map(&:to_s).first(limit)
      by_slug = Section.where(slug: wanted).index_by(&:slug)
      wanted.filter_map { |slug| by_slug[slug] }
    end
  end
end
