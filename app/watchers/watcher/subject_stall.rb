module Watcher
  # Re-entry cost is what kills self-paced learning (docs/EDUCATION_PLAN.md
  # §7), so the stall card's whole job is naming the exact resume point.
  # Signal is SQL: no touch to the subject and no study_log line in two
  # weeks. Monthly-bucketed like goal_stall.
  class SubjectStall < Base
    self.section_slugs = %w[ education ]

    STALL_AFTER = 14.days

    def scan
      user.subjects.active.where(updated_at: ..STALL_AFTER.ago)
          .includes(:sections).find_each do |subject|
        next if subject.topics.none?
        next if user.study_logs.where(subject: subject, on: STALL_AFTER.ago.to_date..).exists?

        topic = subject.current_topic
        next unless topic

        propose(
          fingerprint: "subject:#{subject.id}/#{Date.current.strftime("%Y-%m")}",
          title: "“#{subject.title}” has gone quiet",
          body: "Nothing in two weeks — that's normal, and restarting is the hard part. Next up is “#{topic.title}”; fifteen minutes with the tutor gets it moving.",
          action: { "path" => "/subjects/#{subject.id}", "accept_label" => "Pick it back up" },
          sections: subject.sections.map(&:slug).presence || self.class.section_slugs
        )
      end
    end
  end
end
