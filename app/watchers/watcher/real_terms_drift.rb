module Watcher
  # The quiet pay cut, caught (docs/CAREER.md §4): pay flat on the D30 comp
  # timeline while the CPI-U series on file rose past the threshold. Pure
  # arithmetic over owned data plus a local public dataset — no LLM and no
  # web at nudge time — and it fires for exactly the people who never think
  # to check. No timeline or no dataset → silence, never a guess.
  class RealTermsDrift < Base
    self.section_slugs = %w[ career ]

    THRESHOLD_PERCENT = 5.0

    def scan
      last = Career::CompChange.latest_on(user)
      return unless last

      cpi = Datasets::Cpi.current
      drift = cpi.drift_since(last)
      return unless drift && drift >= THRESHOLD_PERCENT

      propose(
        # Yearly buckets, the raise-cadence convention.
        fingerprint: Date.current.year.to_s,
        title: "Prices are up ~#{drift.round(1)}% since your last pay change",
        body: "Your pay last moved in #{last.strftime("%B %Y")}; CPI-U has risen ~#{drift.round(1)}% " \
              "since (annual averages through #{cpi.latest_year}). Flat pay over that stretch is a " \
              "real-terms cut — worth building the case.",
        kind: :heads_up,
        action: { "tool" => { "slug" => "raise_case" } }
      )
    end
  end
end
