module Tool
  # Billions in benefits and tax credits go unclaimed every year because
  # people don't know they qualify — the highest dollars-per-run tool in the
  # app. The one intake-form tool: a short structured screen beats reading
  # tea leaves from owned data, though Money/People context rides along as
  # color. Tier-A honesty is the hard constraint (this is the tool most at
  # risk of capability lies): the model screens from general program
  # knowledge, phrases everything as "likely within range", and the
  # verify-before-counting-on-it footer — with the screening date — is
  # appended by code. First in line for a live-rules upgrade when Tier B
  # lands (Q9).
  class BenefitsScreener < Base
    self.title = "Am I leaving money on the table?"
    self.description = "A quick screen for benefits and tax credits your household may qualify for."
    self.section_slugs = %w[ benefits ]
    self.kind = :draft

    US_STATES = [
      "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado",
      "Connecticut", "Delaware", "District of Columbia", "Florida", "Georgia",
      "Hawaii", "Idaho", "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky",
      "Louisiana", "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota",
      "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada", "New Hampshire",
      "New Jersey", "New Mexico", "New York", "North Carolina", "North Dakota",
      "Ohio", "Oklahoma", "Oregon", "Pennsylvania", "Puerto Rico", "Rhode Island",
      "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah", "Vermont",
      "Virginia", "Washington", "West Virginia", "Wisconsin", "Wyoming",
      "Outside the United States"
    ].freeze

    CIRCUMSTANCES = [
      "Children under 18",
      "Pregnant or a new baby",
      "60 or older",
      "A disability in the household",
      "A veteran in the household",
      "Recently lost a job",
      "A student in the household",
      "Renting my home",
      "Self-employed"
    ].freeze

    input :state, kind: :select, required: true, options: US_STATES,
      label: "Where do you live?"
    input :household_size, required: true,
      label: "How many people in your household?"
    input :monthly_income, required: true,
      label: "Roughly, monthly household income before taxes",
      hint: "A ballpark is fine — “about $2,800”."
    input :circumstances, kind: :checkboxes, options: CIRCUMSTANCES,
      label: "Which of these apply?"

    MAX_PROGRAMS = 8
    MAX_APPLICATION_TASKS = 5

    Program = Data.define(:name, :likelihood, :why, :first_step) do
      def likely? = likelihood == "likely"
    end

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the benefits-screener feature of a private, self-hosted life
      assistant. The user wants to know which government benefits and tax credits
      their household might qualify for — billions go unclaimed every year simply
      because people don't know to ask. Screen from your general knowledge of
      United States federal programs (SNAP, Medicaid and CHIP, the EITC and Child
      Tax Credit, WIC, LIHEAP, Lifeline, SSI and SSDI, unemployment insurance,
      veterans' benefits, premium tax credits) plus the named state's major
      variants and supplements. Respond with a JSON object:
      {"report": {"title": "...", "body": "..."},
       "programs": [{"name": "...", "likelihood": "likely" or "maybe",
                     "why": "...", "first_step": "..."}, ...]}.
      The report body is a short plain-language read of the household's situation
      as screened: two or three sentences, warm and practical, naming the biggest
      opportunities first. Do not list the programs in the body — they are
      rendered separately from the programs array.
      programs: up to #{MAX_PROGRAMS}, ordered most-valuable first. likelihood is "likely"
      only when the stated income, household size, and circumstances plainly fit
      the program's usual criteria; otherwise "maybe". why names the matching
      facts ("income in usual range for a household of 3", "job loss →
      unemployment insurance"). first_step is the concrete way to start — the
      office, portal, or form by name, never a URL you are not certain exists.
      Honesty rules, non-negotiable: program rules change and your knowledge may
      be out of date, so phrase eligibility as "likely within range", never as a
      promise; never state a specific dollar amount a program will pay ("often
      worth hundreds per month" is the ceiling); never assert a current income
      threshold as fact. If the user lives outside the United States, say plainly
      in the report that this screener knows US programs best, and include only
      programs you are certain exist for their stated location — an empty
      programs list is honest.
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "State: #{inputs[:state]}"
        parts << "Household size: #{inputs[:household_size]}"
        parts << "Monthly household income before taxes: #{inputs[:monthly_income]}"
        circumstances = Array(inputs[:circumstances]).reject(&:blank?)
        parts << "Circumstances: #{circumstances.any? ? circumstances.join("; ") : "none noted"}"
        context = section_context(%w[ money benefits people ])
        parts << "Possibly relevant tracked data (supplementary only — the answers above are the source of truth):\n#{context.to_prompt}" unless context.empty?
        parts.join("\n\n")
      end

      def handle(response)
        body = response.dig("report", "body")
        raise Llm::Error, "The model didn't return a screening report — try again." if body.blank?

        programs = parsed_programs(response["programs"])

        create_note(
          title: response.dig("report", "title").presence || "Benefits screen — #{Date.current.strftime("%B %Y")}",
          body: [
            body,
            program_block("Likely — worth applying", programs.select(&:likely?)),
            program_block("Worth checking", programs.reject(&:likely?)),
            verify_footer
          ].compact.join("\n\n")
        )

        programs.select(&:likely?).first(MAX_APPLICATION_TASKS).each do |program|
          create_task(title: "Start the #{program.name} application", notes: program.first_step)
        end
      end

      def parsed_programs(list)
        Array(list).first(MAX_PROGRAMS).filter_map do |entry|
          next unless entry.is_a?(Hash) && entry["name"].present?

          Program.new(
            name: entry["name"].to_s,
            likelihood: entry["likelihood"].to_s == "likely" ? "likely" : "maybe",
            why: entry["why"].to_s.strip.presence,
            first_step: entry["first_step"].to_s.strip.presence
          )
        end
      end

      def program_block(heading, programs)
        return nil if programs.none?

        lines = programs.map do |program|
          detail = [ program.why, ("First step: #{program.first_step}" if program.first_step) ].compact.join(" ")
          "- #{program.name}#{" — #{detail}" if detail.present?}"
        end
        "#{heading}:\n#{lines.join("\n")}"
      end

      # Appended by code, never left to the model: this tool's honesty
      # depends on the user verifying before counting on anything.
      def verify_footer
        "Program rules and income limits change — treat this as a starting point " \
          "and verify each program at its official site before counting on it. " \
          "Screened #{Date.current.strftime("%B %-d, %Y")}."
      end
  end
end
