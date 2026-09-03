module Documents
  # The Save click on the review page (D-document-intake): the checked
  # landings — with whatever the user edited — go back through their kinds'
  # coercion, and only when every one of them passes do they land, in one
  # transaction, with provenance recorded. Unchecked ones are marked
  # skipped, not deleted, so re-analysis never proposes them again and the
  # page keeps a way back to them.
  #
  # `submissions` is the review form's params: index → {keep, attributes}.
  # An index the form didn't mention is treated as unchecked, which is what
  # makes "Skip all" a plain submit with nothing ticked.
  class Land
    Result = Data.define(:saved, :drafts) do
      def ok? = drafts.all?(&:valid?)
    end

    def initialize(document:, user:, submissions:)
      @document = document
      @user = user
      # Permitted params or a plain hash; `to_h` raises on unpermitted
      # Parameters, which is the guard rather than a nuisance — the
      # controller permits per kind against the registry.
      @submissions = submissions.to_h.stringify_keys
      @context = Landing::Context.new(user: user, document: document)
    end

    def call
      drafts = proposed_drafts
      kept = drafts.select(&:keep?)
      return Result.new(saved: [], drafts: drafts) unless kept.all?(&:valid?)

      saved = []
      @document.transaction do
        landings = @document.landings.deep_dup
        drafts.each do |draft|
          entry = landings[draft.index]
          if draft.keep?
            record = draft.landing_class.new(@context).land!(draft.attributes, sections: @context.filing)
            @document.document_items.create!(item: record, fingerprint: draft.fingerprint)
            entry.merge!("status" => "saved", "attributes" => draft.attributes,
              "item_type" => record.class.name, "item_id" => record.id)
            saved << record
          else
            entry["status"] = "skipped"
          end
        end
        @document.update!(landings: landings)
      end

      Result.new(saved: saved, drafts: drafts)
    end

    # Every proposed entry as a Draft: kept ones re-coerced from the
    # submitted attributes (falling back to the proposed ones, so a field
    # the form didn't render keeps its value), skipped ones as they were.
    def proposed_drafts
      @document.landing_drafts(@context).select { |draft| draft.status == "proposed" }.map do |draft|
        submitted = @submissions[draft.index.to_s] || {}
        keep = submitted["keep"].to_s == "1"
        next draft.tap { |d| d.keep = false } unless keep

        kind = draft.landing_class.new(@context)
        edited = draft.attributes.merge((submitted["attributes"] || {}).to_h.stringify_keys)
        kind.coerce(edited).tap do |coerced|
          coerced.index = draft.index
          coerced.keep = true
          coerced.fingerprint = draft.fingerprint
          coerced.flags = draft.flags
        end
      end
    end
  end
end
