# The landing registry (D-landing-registry): the one list of the kinds of
# row a model may propose and code may write. Each kind is a class under
# Landing:: that declares its fields once; from that declaration come the
# prompt paragraph the model is shown, the validation of its answer into
# the closed set, the write, the review-page preview, and the form the
# review page edits with. Nothing else in the app knows a kind's fields.
#
# Two consumers today: document intake (Documents::Analyze proposes,
# Documents::Land writes) and the agent's prepared work (ToolRun#land!).
# Registered here, on the Tool::SLUGS pattern, so the registry is code —
# first-party only (D11) — and the drift guard in test/landings can read it.
module Landing
  KINDS = %w[ event task note person medication allergy pet_facts pet_food pet_vaccination spending ].freeze

  # Primitives paper does not produce, each with the reason (INTAKE_PLAN
  # §2). The registry test holds every key of Users::Export::MODELS to one
  # of two accounts: a kind that `produces` it, or a line here. Adding a
  # primitive without deciding which is a red test.
  NOT_INTAKE = {
    "documents" => "the document is the thing being read; it never proposes itself",
    "photos" => "a photo of a photo is a photo — it belongs in the library, uploaded there",
    "albums" => "curation, not a fact a document states",
    "goals" => "an intention, not a fact; the breakdown pipeline owns goals (D17)",
    "credentials" => "a password on paper goes through the vault's own form and never through a model",
    "feeds" => "a subscription is chosen, not read off paper",
    "suggestions" => "the agent's own output surface (D20)",
    "recipes" => "has its own paste-import with a deterministic parser (RECIPES_PLAN §5.1); intake routes to it rather than re-implementing it",
    "recipe_books" => "curation, as albums",
    "spending_accounts" => "an account is set up, not extracted",
    "budget_categories" => "envelopes are the user's own budget decisions",
    "spending_rules" => "the user's explicit rules (D-no-keyword-logic), never inferred"
  }.freeze

  # The most a single document may propose. A discharge sheet is six or
  # seven; past a dozen the model is inventing granularity.
  MAX_LANDINGS = 12

  module_function

  def all = KINDS.map { |kind| find(kind) }

  def find(kind)
    const_get(kind.to_s.camelize) if KINDS.include?(kind.to_s)
  end

  def find!(kind)
    find(kind) || raise(ArgumentError, "no landing kind named #{kind.inspect}")
  end

  # The paragraph that tells the model what the household stores — generated
  # from the kinds' declarations, never hand-written, so it cannot fall
  # behind the code that validates and writes (D-landing-registry).
  def prompt_block(context, kinds: all)
    lines = kinds.map { |kind| kind.prompt_line(context) }
    parts = [ "The household stores these kinds of things. For each, add an entry to \"landings\" " \
              "only when the document plainly states it:\n#{lines.join("\n")}" ]
    parts << rules
    listings = kinds.flat_map(&:fields).filter_map { |field| field.ref }.uniq.filter_map { |ref| context.ref_listing(ref) }
    parts.concat(listings)
    parts.join("\n\n")
  end

  # The presence pass's block (INTAKE_PLAN §3): kind names and what they
  # are, so a small model can say *which* kinds a document contains before
  # being shown any kind's fields — asking about less, never swapping the
  # mechanism (D-no-keyword-logic).
  def names_block
    "The household stores these kinds of things:\n#{all.map(&:name_line).join("\n")}\n" \
    "List in \"present_kinds\" the kinds this document plainly contains something of, by name; [] if none."
  end

  def present_kinds(raw)
    Array(raw).map(&:to_s).uniq.filter_map { |kind| find(kind) }
  end

  def rules
    <<~RULES.strip
      Rules for landings: copy names, dates and numbers as printed; omit any field the document
      doesn't give rather than guessing; one entry per fact, never a duplicate; a visit that
      already happened is an event in the past and a stated due date is an event in the future;
      at most #{MAX_LANDINGS} entries. Every entry carries "kind" plus that kind's fields.
    RULES
  end

  # The model's answer, validated into entries the document can hold:
  # unknown kinds dropped, each kind's fields coerced, entries missing a
  # required field dropped, duplicates within the batch collapsed, capped.
  def propose(raw, context)
    Array(raw).first(MAX_LANDINGS * 2).filter_map do |entry|
      next unless entry.is_a?(Hash)

      kind = find(entry["kind"].to_s) or next
      landing = kind.new(context)
      attributes = landing.validate(entry.except("kind")) or next

      { "kind" => kind.kind, "fingerprint" => landing.fingerprint(attributes),
        "status" => "proposed", "attributes" => attributes }
    end.uniq { |entry| entry["fingerprint"] }.first(MAX_LANDINGS)
  end
end
