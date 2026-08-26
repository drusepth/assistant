module Watcher
  # Only for subjects whose learner set a target date (D-mastery-evidence:
  # pace is measured against their own anchor, never an age-grade norm) —
  # ahead needs no card; behind gets computed honestly and phrased kindly,
  # with every honest exit named.
  class PaceCheck < Base
    self.section_slugs = %w[ education ]

    def scan
      user.subjects.active.where.not(target_date: nil)
          .where(target_date: Date.current..).includes(:sections).find_each do |subject|
        next unless subject.pace == :behind

        days_left = (subject.target_date - Date.current).to_i
        propose(
          fingerprint: "pace:#{subject.id}/#{Date.current.strftime("%Y-%m")}",
          kind: :heads_up,
          title: "“#{subject.title}” is behind its target",
          body: "#{subject.mastered_count} of #{subject.leaf_count} topics mastered, #{days_left} days to go. The pace is yours: lean in, trim the syllabus, or move the date — all three are winning.",
          action: { "path" => "/subjects/#{subject.id}", "accept_label" => "Look at the syllabus" },
          sections: subject.sections.map(&:slug).presence || self.class.section_slugs
        )
      end
    end
  end
end
