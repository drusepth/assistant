module Watcher
  # The queue crossed the worth-mentioning line (D-review-scheduler): one
  # nudge with the honest minutes, weekly-bucketed so a dismissal sticks for
  # a while. The count is SQL; there is nothing here for a model to decide.
  class ReviewsDue < Base
    self.section_slugs = %w[ education ]

    THRESHOLD = 5

    def scan
      due = user.review_items.due.count
      return if due < THRESHOLD

      minutes = [ (due / 2.0).ceil, 1 ].max
      propose(
        fingerprint: "due/#{Date.current.strftime("%G-w%V")}",
        title: "#{due} review cards are due",
        body: "About #{minutes} minutes shores up what's slipping — recall is what makes it stick.",
        action: { "path" => "/reviews", "accept_label" => "Review now" }
      )
    end
  end
end
