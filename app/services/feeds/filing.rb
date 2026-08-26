module Feeds
  # Where a feed goes the moment it exists (D-hobby-feeds), and the one place
  # that decides. Three cases, in this order:
  #
  #   1. the user picked lenses in the form — nothing to decide, and the
  #      model never overrules a human's filing;
  #   2. a model is configured — ask it, in a job (ClassifyFeedJob);
  #   3. no model — the catch-all, immediately.
  #
  # Case 3 is the reader's third promise in one line: an instance with no API
  # key still follows feeds, still splits them by hobby, and still shows the
  # hub. It just files by hand.
  module Filing
    module_function

    def call(feed)
      return if feed.sections.any?

      feed.enqueue_auto_sort! || ::Hobbies::OtherInterests.absorb!([ feed ])
    end

    # "Re-file this feed": the user's own request to ask again, so it runs
    # even for a feed that already has lenses — that is what makes it a
    # re-file rather than a no-op.
    def refile(feed)
      return false unless feed.auto_sort_profile

      feed.sections = []
      ClassifyFeedJob.perform_later(feed)
      true
    end
  end
end
