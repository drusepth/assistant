module Tool
  # The tool the win log and comp timeline exist for (docs/CAREER.md §3.4).
  # Reads the receipts — logged wins, the last recorded pay change and the
  # tenure math code computes from it — and lands a raise-case memo the user
  # could paste straight into an email, plus the checklist of market numbers
  # to fetch and where. Tier-A honesty: the model never asserts a market
  # rate; it names exactly what to look up. Routes onward to negotiation
  # prep, which turns the case plus the fetched numbers into the script.
  class RaiseCase < Base
    self.title = "Build my raise case"
    self.description = "Your logged wins and tenure math as a memo you could send — plus the numbers to fetch."
    self.section_slugs = %w[ career ]
    self.kind = :draft

    input :role,
      label: "Your job title",
      hint: "Optional — lets the memo cite the closest national wage medians when the dataset is loaded."
    input :extras, kind: :textarea,
      label: "Anything not tracked here?",
      hint: "Optional — wins you never logged, duties you've taken on, your target number."

    MAX_FOLLOW_UPS = 2
    MAX_RESEARCH = 5
    ROUTABLE_SLUGS = %w[ negotiation_prep ].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the raise-case feature of a private, self-hosted life assistant.
      The user is preparing to ask for a raise; their employer prices labor
      every week and they do this once every few years. Build the case from
      their receipts. Respond with a JSON object:
      {"memo": {"title": "...", "body": "..."},
       "research": ["...", ...],
       "follow_ups": [{"title": "...", "due_on": "YYYY-MM-DD" or null}, ...]}.
      The memo is a document the user could paste into an email to their
      manager — professional, factual, zero pleading:
      - What they've delivered: the tracked wins grouped by what each did for
        the business (money saved, errors caught, coverage carried), phrased
        as results. Use ONLY what their data states; never inflate.
      - What's grown: duties and scope added since the last pay change, as
        their record shows it.
      - The timing: the tenure-since-last-change math provided below, stated
        plainly ("my pay was last adjusted N months ago").
      - The ask: a clear request line with a [BRACKETED PLACEHOLDER] where
        the target number goes, and one sentence of collaborative framing.
      Never invent market rates, percentages, or comparable salaries — where
      a market number would strengthen the case, leave a [BRACKETED
      PLACEHOLDER] naming exactly what to look up. The one exception: when
      the user prompt includes "public data on file" (CPI buying-power drift,
      national wage medians), those ARE sourced numbers — weave them into the
      memo with their vintage stated, phrased as reference points to verify,
      not as this user's personal market rate.
      research: at most #{MAX_RESEARCH} specific numbers to fetch before the ask, each
      naming where — the BLS occupational wage table for this kind of role,
      state or city wage data, current postings for the same title nearby.
      follow_ups: at most #{MAX_FOLLOW_UPS} (fetch the numbers, book the conversation).
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
        parts << tenure_line
        parts.concat(public_data_lines)
        parts << "Untracked context from the user: #{inputs[:extras]}" if inputs[:extras].present?
        context = section_context
        unless context.empty?
          parts << "The user's tracked career record — logged wins, work history, pay-change events:\n#{context.to_prompt}"
        end
        parts << web_capability_note
        parts.compact.join("\n\n")
      end

      # Code states the timeline fact; the model only phrases it.
      def tenure_line
        if (last = Career::CompChange.latest_on(user))
          months = (Date.current.year * 12 + Date.current.month) - (last.year * 12 + last.month)
          "The user's pay last changed on #{last.iso8601} — #{months} months ago."
        else
          "No pay change is recorded. The memo's timing section should carry a " \
          "[BRACKETED PLACEHOLDER] for when pay was last adjusted."
        end
      end

      # The public datasets (D-public-datasets), when loaded: code fetches
      # the numbers, the model only phrases them — vintage always attached.
      def public_data_lines
        lines = []
        if (last = Career::CompChange.latest_on(user))
          cpi = Datasets::Cpi.current
          if (drift = cpi.drift_since(last))
            lines << "Public data on file — buying power: CPI-U rose ~#{drift.round(1)}% between " \
                     "#{last.year} and #{cpi.latest_year} (annual averages). Flat pay since " \
                     "#{last.strftime("%B %Y")} is a real-terms cut of about that size."
          end
        end
        if inputs[:role].present? && (wages = Datasets::Wages.current).present?
          matches = wages.search(inputs[:role])
          if matches.any?
            rows = matches.map do |occupation|
              median = [ occupation.hourly_median && "$#{occupation.hourly_median}/hr median",
                         occupation.annual_median && "$#{occupation.annual_median.round}/yr median" ].compact.join(", ")
              "- #{occupation.title}: #{median.presence || "median not published"}"
            end
            lines << "Public data on file — national wage medians (BLS OEWS, #{wages.as_of}), closest " \
                     "title matches to “#{inputs[:role]}”; offer as national reference points, local " \
                     "rates still worth fetching:\n#{rows.join("\n")}"
          end
        end
        lines
      end

      def handle(response)
        body = response.dig("memo", "body")
        raise Llm::Error, "The model didn't return a memo — try again." if body.blank?

        research = bulleted_block("Numbers to fetch before the ask", response["research"], limit: MAX_RESEARCH)
        create_note(
          title: response.dig("memo", "title").presence || "Raise case — #{Date.current.strftime("%B %Y")}",
          body: [ body, research ].compact.join("\n\n")
        )
        create_follow_ups(response["follow_ups"], limit: MAX_FOLLOW_UPS)
        store_next_tools(
          [ { "slug" => "negotiation_prep",
              "inputs" => { "scenario" => "Asking for a raise" },
              "reason" => "The case is built — negotiation prep turns it into the script and the counter." } ],
          allowed: ROUTABLE_SLUGS
        )
      end
  end
end
