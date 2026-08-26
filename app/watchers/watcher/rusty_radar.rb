module Watcher
  # Mastered-and-decayed, surfaced kindly (D-mastery-evidence): the rusty
  # sweep already told the truth on the tile; this says it where the user
  # will see it, with the honest price — minutes, not months.
  class RustyRadar < Base
    self.section_slugs = %w[ education ]

    def scan
      rusty = Topic.joins(:subject)
        .where(subjects: { user_id: user.id }, mastery: :rusty)
        .order(:mastered_on).to_a
      return if rusty.empty?

      named = rusty.first(2).map { |topic| "“#{topic.title}”" }.join(" and ")
      title = rusty.one? ? "A mastered topic has gone rusty" : "#{rusty.size} mastered topics have gone rusty"
      propose(
        fingerprint: "rusty/#{Date.current.strftime("%Y-%m")}",
        title: title,
        body: "#{named} #{rusty.one? ? "has" : "have"} slipped past likely recall. A few minutes of review re-earns the green — mastered means maintained.",
        action: { "path" => "/reviews", "accept_label" => "Shore it up" }
      )
    end
  end
end
