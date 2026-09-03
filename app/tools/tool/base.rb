module Tool
  # Declarative superclass for tool definitions. A subclass names itself for
  # the Act zone (title/description), registers on section slugs, declares
  # the minimal inputs its form asks for (D16: only what can't be read from
  # owned data), and implements the LLM round-trip.
  #
  # Draft tools (kind :draft) share one response contract — DRAFT_FORMAT —
  # and the default `handle` lands it: a draft Note plus up to MAX_FOLLOW_UPS
  # follow-up Tasks, all filed under `filing`. A draft tool usually only
  # writes `messages` and overrides `filing`/`fallback_title` when the
  # defaults aren't right.
  #
  # Plan tools (kind :plan) override `call` with one line: `plan_goal!` —
  # goal capture with framing, riding the same Goals::BreakDown pipeline as
  # every goal. No tool adds schema or pipeline of its own.
  #
  # Chat tools (kind :chat) ride ChatBase — see that class and D29.
  #
  # Beneath the three kinds sits a shared helper layer (TOOLS_PLAN):
  # visibility-walled `chosen_document`, budgeted `section_context`,
  # `create_*` landing helpers (deadlines land as all-day calendar Events),
  # and `store_next_tools` — the D28 routing seam.
  class Base
    Input = Data.define(:name, :label, :kind, :required, :hint, :options, :prefill) do
      def required? = required
      def document? = kind == :document
      def person? = kind == :person
      # A tool that takes a pet reads her species, age, weight, diet and
      # meds from the record instead of asking (D-pet-primitive) — the
      # `person`/`hobby` convention, applied to the household's other members.
      def pet? = kind == :pet
      def hobby? = kind == :hobby
      def select? = kind == :select
      def checkboxes? = kind == :checkboxes
      def email_message? = kind == :email_message
      def budget_category? = kind == :budget_category
      def ledger_month? = kind == :ledger_month
      def textarea? = kind == :textarea
      def date? = kind == :date
      def topic? = kind == :topic
      def study_subject? = kind == :study_subject
    end

    class_attribute :title, :description, :kind, instance_accessor: false, default: nil
    class_attribute :section_slugs, instance_accessor: false, default: []
    class_attribute :input_definitions, instance_accessor: false, default: []
    # Whether the agent may run this tool unbidden to have a draft waiting
    # (D-agent-prepared-work). A tool opts out when its run is too slow or
    # too web-bound to spend on a click that may never come; only draft
    # tools are ever eligible in the first place.
    class_attribute :preparable, instance_accessor: false, default: true

    MAX_FOLLOW_UPS = 3
    MAX_DEADLINES = 3
    MAX_NEXT_TOOLS = 2
    MAX_DOCUMENT_CHARS = 15_000

    DRAFT_FORMAT = <<~PROMPT.freeze
      Respond with a JSON object:
      {"draft": {"title": "...", "body": "..."},
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      follow_ups are at most #{MAX_FOLLOW_UPS} small concrete actions, each completable
      within a single day; set due_on only when a real deadline is stated or
      clearly implied, resolved against today's date.
      Invent nothing — where a detail is unknown, leave a [BRACKETED
      PLACEHOLDER] for the user to fill in.
    PROMPT

    class << self
      def slug = name.demodulize.underscore

      # prefill: a User method whose value seeds the form field when the
      # user hasn't typed one (D-work-profile) — profile facts arrive
      # pre-filled and stay editable, instead of being asked for again.
      def input(name, label:, kind: :text, required: false, hint: nil, options: nil, prefill: nil)
        self.input_definitions += [ Input.new(name: name.to_s, label:, kind:, required:, hint:, options:, prefill:) ]
      end

      def inputs = input_definitions

      def section_records = Section.where(slug: section_slugs).order(:parent_id, :position)
    end

    def initialize(run)
      @run = run
      @user = run.user
      @landings = []
    end

    # What this run would have created, when it ran in preparation mode —
    # the `Watcher::Base#proposals` convention: the caller reads the work
    # off the instance rather than the instance writing it anywhere.
    attr_reader :landings

    # The template method ToolRunJob calls. Everything user-facing that can
    # go wrong raises Llm::Error so the run fails with a friendly message.
    def call
      handle(profile.client.chat(messages, json: true))
    end

    private
      attr_reader :run, :user

      # Default landing for the DRAFT_FORMAT contract.
      def handle(response)
        body = response.dig("draft", "body")
        raise Llm::Error, "The model didn't return a draft — try again." if body.blank?

        create_note(title: response.dig("draft", "title").presence || fallback_title, body: body)
        create_follow_ups(response["follow_ups"])
      end

      # Where a draft tool's output is filed. Default: where the tool lives,
      # plus the filing of whatever owned items the run read (a letter about
      # a Health-tagged bill lands in Disputes and Health).
      def filing
        @filing ||= (self.class.section_records + filing_sources.compact.flat_map(&:sections)).uniq
      end

      # Owned items whose sections the output inherits; subclasses override.
      def filing_sources = []

      def fallback_title = "#{self.class.title} — draft"

      # The whole plan-tool contract: create a plain Goal, hand it to the
      # shared breakdown pipeline with framing, record what comes back.
      def plan_goal!(title:, brief:, description: nil)
        goal = record(user.goals.create!(title: title, description: description))
        begin
          Goals::BreakDown.new(goal: goal, profile: profile, brief: brief).plan!.each { |task| record(task) }
          # The plan is always findable where the tool lives, on top of
          # whatever the model filed it under.
          goal.sections = (goal.sections.to_a + self.class.section_records).uniq
        ensure
          # Stamp even on failure so the goal card can't spin forever — a
          # failed run leaves an ordinary unplanned goal the user can retry
          # from its own page, and the board refreshes either way.
          goal.update_column(:broken_down_at, Time.current)
          Turbo::StreamsChannel.broadcast_refresh_to(user, :tasks)
        end
        goal
      end

      def profile
        profile = user.household.model_profile
        unless profile&.configured?
          raise Llm::Error, "Tools need an AI model — ask your household admin to configure one in Settings."
        end
        profile
      end

      def inputs = run.inputs.with_indifferent_access

      # Created primitives are recorded on the run so its page can show them.
      def record(item)
        run.tool_run_items.create!(item: item)
        item
      end

      # ── Owned context ──────────────────────────────────────────────────

      # The document an input points at, read through the visibility wall.
      # A blank input returns nil (for tools where the document is optional);
      # a chosen document that vanished or was unshared raises, because the
      # user picked it and silence would draft a letter about nothing.
      def chosen_document(input_name = :document_id)
        return nil if inputs[input_name].blank?

        (@chosen_documents ||= {})[input_name.to_s] ||=
          Document.visible_to(user).find_by(id: inputs[input_name]) ||
            raise(Llm::Error, "That document is gone or no longer shared with you.")
      end

      # The person an input points at, through the visibility wall — same
      # contract as chosen_document: blank input nil, vanished pick raises.
      def chosen_person(input_name = :person_id)
        return nil if inputs[input_name].blank?

        (@chosen_people ||= {})[input_name.to_s] ||=
          Person.visible_to(user).find_by(id: inputs[input_name]) ||
            raise(Llm::Error, "That person is gone or no longer shared with you.")
      end

      # The pet an input points at, through the visibility wall — same
      # contract as chosen_document.
      def chosen_pet(input_name = :pet_id)
        return nil if inputs[input_name].blank?

        (@chosen_pets ||= {})[input_name.to_s] ||=
          Pet.visible_to(user).find_by(id: inputs[input_name]) ||
            raise(Llm::Error, "That pet is gone or no longer shared with you.")
      end

      # What's known about a pet, assembled once for every pet tool
      # (D-pet-primitive): the record, the diet with its history, the
      # medications and the recent care. All of it read rather than asked
      # for — the D16 rule, and the reason a `:pet` input is one dropdown.
      def pet_context(pet, viewer: user)
        parts = [ "Name: #{pet.name}", "Species: #{pet.species_label}" ]
        parts << "Breed: #{pet.breed}" if pet.breed.present?
        parts << "Sex: #{pet.sex_label}" if pet.sex_label
        # So a model writes "he" about a male dog and "they" about a pet whose
        # sex nobody recorded, instead of defaulting to one of them.
        parts << "Refer to this pet as: #{pet.pronouns.slashed}"
        parts << "Age: #{pet.age_phrase}" if pet.age_phrase
        parts << "Weight: #{pet.weight_kg} kg" if pet.weight_kg
        parts << "What the owner has noted:\n#{pet.notes.truncate(1_500)}" if pet.notes.present?

        shelf = Pets::FoodShelf.new(pet)
        current = shelf.current.map { |food| "- #{food.display_name} (#{food.form_label})#{", #{food.daily_phrase}" if food.daily_phrase}, since #{food.started_on.iso8601}" }
        parts << "Currently eating:\n#{current.join("\n")}" if current.any?
        history = shelf.past.first(5).map { |food| "- #{food.display_name}: #{food.started_on.iso8601} to #{food.ended_on.iso8601}" }
        parts << "Previously eaten (the diet history a vet asks for):\n#{history.join("\n")}" if history.any?

        meds = pet.items(Note, viewer).medications.limit(10).map { |note| [ note.title, note.body ].compact.join(" — ") }
        parts << "Medications on file:\n#{meds.map { |med| "- #{med}" }.join("\n")}" if meds.any?

        care = pet.items(Event, viewer).where(starts_at: 24.months.ago..).order(:starts_at).limit(15)
          .map { |event| "- #{event.starts_at.to_date.iso8601} — #{event.title}" }
        parts << "Care on the calendar (past two years and upcoming):\n#{care.join("\n")}" if care.any?

        parts.join("\n")
      end

      # What's known about a person, assembled once for every People tool
      # (docs/PEOPLE.md §4): profile fields, filing, the user's own notes.
      # When Q17 person↔item links land, shared history joins here.
      def person_context(person)
        parts = [ "Name: #{person.name}" ]
        # Without this a model picks a pronoun off the name, which is a guess
        # dressed as knowledge and lands in a draft the user is about to send
        # to that person. Sent even when nothing is recorded, because
        # "they/them/their" is the answer then, not an absent line (D-pronouns).
        parts << "Refer to them as: #{person.pronouns.slashed}"
        parts << "Relationship: #{person.relationship}" if person.relationship.present?
        parts << "Birthday: #{person.birthday.strftime("%B %-d")}" if person.birthday
        parts << "Last logged contact: #{person.last_contacted_on.iso8601}" if person.last_contacted_on
        filed = person.sections.map(&:qualified_name)
        parts << "Filed under: #{filed.join(", ")}" if filed.any?
        parts << "What the user has noted about them:\n#{person.notes.truncate(2_000)}" if person.notes.present?
        parts.join("\n")
      end

      def document_text(document)
        text = document.extracted_text.presence || document.summary.presence
        raise Llm::Error, "That document has no readable text yet — open it and run Analyze first." unless text

        text.truncate(MAX_DOCUMENT_CHARS)
      end

      # Owned items in the given sections (default: where the tool lives),
      # through the visibility wall, as a budgeted prompt block.
      def section_context(slugs = self.class.section_slugs, budget: Context::DEFAULT_BUDGET)
        Context.new(user: user, section_slugs: slugs, budget: budget)
      end

      # The household's jurisdiction (D34) for state-sensitive tools — nil
      # when unset, so prompts fall back to asking or to placeholders.
      def region_line
        region = user.household.region
        "Where the household lives (tailor jurisdiction-specific details to this): #{region}" if region.present?
      end

      # The user's stated work (D-work-profile) for Career tools — nil when
      # unset, so prompts fall back to asking or to placeholders, same
      # contract as region_line. Stated by the user in Settings, never
      # inferred (Q8): the model may treat it as fact.
      def work_line
        summary = user.work_summary
        "The user's current work, from their profile (treat as stated fact): #{summary}" if summary
      end

      # The household's own return address (D-household-profile), for tools
      # that draft something addressed *from* the house. Deliberately opt-in
      # per tool rather than folded into `region_line`: a street address is
      # the most identifying thing the household stores, and it goes to the
      # model only where a letterhead genuinely needs it.
      def sender_address_block
        household = user.household
        lines = household.address_lines
        return if lines.empty? && household.phone.blank?

        [ "The sender's own contact details (use them verbatim on the letterhead — do not invent or bracket these):",
          user.name, *lines, household.phone.presence ].compact.join("\n")
      end

      # The app-side web floor (D-career-web): fetch one user-supplied URL through
      # Web::Fetch (deterministic code, SSRF-guarded, size-capped) and hand
      # the model the text. A blank input is nil; a failed fetch fails the
      # run with a message that names the paste-the-text fallback.
      def fetched_page(input_name = :listing_url)
        return nil if inputs[input_name].blank?

        (@fetched_pages ||= {})[input_name.to_s] ||= begin
          Web::Fetch.text(inputs[input_name])
        rescue Web::Fetch::Error => e
          raise Llm::Error, "Couldn't fetch that link — #{e.message}. Pasting the text works too."
        end
      end

      # The model-side rung (D-career-web): when the admin has declared the
      # provider web-capable, prompts may relax never-assert-current-facts
      # into look-it-up-and-cite. Nil otherwise, so callers compact it away.
      def web_capability_note
        return nil unless profile.web_capable?

        "The configured model has live web access: where these instructions say to never assert " \
        "current facts, you may instead look them up and cite what you found — keeping fetched " \
        "facts clearly separate from the user's own records."
      end

      # ── Landing primitives ─────────────────────────────────────────────

      # In preparation mode (D-agent-prepared-work) these three write down
      # what they *would* have created and hand back an unsaved record, so
      # the agent's speculative run leaves nothing in Browse, Calendar,
      # Today or search until the user's Save replays the intents. Tool
      # subclasses are unchanged by any of it — routing preparation through
      # the same classes, prompts and filing is the whole point.
      def create_note(title:, body:)
        return stage("note", { "title" => title, "body" => body }, user.notes.new(title:, body:)) if preparing?

        note = record(user.notes.create!(title:, body:))
        note.sections = filing
        note
      end

      def create_task(title:, due_on: nil, notes: nil)
        bucket = due_on && due_on <= Date.current ? :today : :later
        if preparing?
          return stage("task", { "title" => title, "notes" => notes, "due_on" => due_on&.iso8601 },
            user.tasks.new(title:, notes:, due_on:, bucket:))
        end

        task = record(user.tasks.create!(title:, notes:, due_on:, bucket:))
        task.sections = filing
        task
      end

      # Deadlines land as all-day Events: a Task can be snoozed, a date on
      # the calendar is harder to lose — and it surfaces in Calendar/Today
      # like everything else.
      def create_event(title:, on:, description: nil)
        if preparing?
          return stage("event", { "title" => title, "description" => description, "on" => on&.to_date&.iso8601 },
            user.events.new(title:, description:, starts_at: on&.in_time_zone, all_day: true))
        end

        event = record(user.events.create!(
          title:, description:, starts_at: on.in_time_zone, all_day: true
        ))
        event.sections = filing
        event
      end

      def preparing? = run.preparing.present?

      # Records the intent — including the filing, resolved now so the Save
      # click files exactly where an ordinary run would have — and returns
      # the unsaved record, so a caller reading the result back still can.
      def stage(kind, attributes, item)
        @landings << attributes.compact.merge("kind" => kind, "sections" => filing.map(&:id))
        item
      end

      # The response-shape parsers shared by the draft-tool family: arrays
      # of {"title", "due_on"/"date"} hashes, malformed entries dropped.
      def create_follow_ups(steps, limit: MAX_FOLLOW_UPS)
        Array(steps).first(limit).each do |step|
          next unless step.is_a?(Hash) && step["title"].present?

          create_task(title: step["title"].to_s, due_on: parsed_date(step["due_on"]))
        end
      end

      def create_deadline_events(deadlines, limit: MAX_DEADLINES)
        Array(deadlines).first(limit).each do |deadline|
          next unless deadline.is_a?(Hash) && deadline["title"].present?

          date = parsed_date(deadline["date"])
          create_event(title: deadline["title"].to_s, on: date) if date
        end
      end

      # ── Routing (D28) ──────────────────────────────────────────────────

      # Tools compose by routing, never by calling each other: the model
      # proposes follow-on tools, code sanitizes — only slugs the caller
      # allows, only inputs the target declares — and the run page renders
      # what survives as prefilled next-step cards the user clicks through.
      def store_next_tools(proposals, allowed:)
        sanitized = Array(proposals).filter_map do |proposal|
          next unless proposal.is_a?(Hash)

          tool = Tool.find(proposal["slug"].to_s)
          next unless tool && tool != self.class && allowed.include?(tool.slug)

          {
            "slug" => tool.slug,
            "inputs" => sanitized_inputs(tool, proposal["inputs"]),
            "reason" => proposal["reason"].to_s.strip.presence
          }.compact
        end.uniq { |entry| entry["slug"] }.first(MAX_NEXT_TOOLS)

        run.update!(output: run.output.merge("next_tools" => sanitized)) if sanitized.any?
      end

      def sanitized_inputs(tool, inputs)
        return {} unless inputs.is_a?(Hash)

        inputs.slice(*tool.inputs.map(&:name))
          .transform_values(&:to_s)
          .reject { |_name, value| value.blank? }
      end

      # "Heading:\n- item" blocks are assembled by code so list formatting
      # never depends on model behavior.
      def bulleted_block(heading, items, limit:)
        items = Array(items).grep(String).map(&:strip).reject(&:empty?).first(limit)
        return nil if items.none?

        "#{heading}:\n#{items.map { |item| "- #{item}" }.join("\n")}"
      end

      def parsed_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        nil
      end
  end
end
