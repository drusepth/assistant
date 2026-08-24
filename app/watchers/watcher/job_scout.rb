module Watcher
  # The job scout (D-career-web) — the first watcher allowed off the SQL-only leash:
  # it fetches the user's configured feeds (Web::Fetch, ToS-clean sources
  # only) and makes one model call to rank fresh postings against the
  # tracked record across Career, Hobbies, and Education. What survives is
  # enjoyment-aware, not title-matching. The D20 write surface holds
  # completely: suggestions only, propose-don't-dispose — accept opens
  # Tailor-my-application prefilled with the posting's link; nothing is
  # ever applied to.
  class JobScout < Base
    self.section_slugs = %w[ career ]

    MAX_PICKS = 3
    POSTINGS_TO_RANK = 60

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the job-scout feature of a private, self-hosted life assistant.
      From the numbered postings, pick the few that genuinely fit this user —
      their work history, their constraints, and what their hobbies and
      learning say they'd actually enjoy. Respond with a JSON object:
      {"picks": [{"index": 0, "reason": "..."}, ...]}.
      At most #{MAX_PICKS} picks; each reason is one line in the user's terms, naming
      what in THEIR record makes it a fit. An empty list is the right answer
      when nothing truly fits — the user's attention is the scarce resource,
      and a bad lead costs trust.
    PROMPT

    def scan
      feeds = user.job_feeds.due_for_scan.to_a
      return if feeds.empty?

      profile = user.household.model_profile
      return unless profile&.configured?

      fresh = unseen(feeds.flat_map { |feed| scan_feed(feed) }).first(POSTINGS_TO_RANK)
      return if fresh.empty?

      picks(profile, fresh).each do |posting, reason|
        role = [ posting.title, posting.company ].compact.join(" at ")
        propose(
          # One suggestion per posting, ever — a dismissed lead stays gone.
          fingerprint: fingerprint_for(posting),
          title: "Job lead: #{role}",
          body: [ reason, posting.location && "Location: #{posting.location}", posting.url ].compact.join("\n"),
          kind: :heads_up,
          action: { "tool" => { "slug" => "tailor_application",
                                "inputs" => { "role" => role, "listing_url" => posting.url } } }
        )
      end
    end

    private
      def scan_feed(feed)
        page = Web::Fetch.text(feed.fetch_url, headers: feed.fetch_headers)
        feed.update!(last_scanned_at: Time.current, last_error: nil)
        Career::FeedParser.parse(feed.kind, page.text, fallback_company: feed.company_hint)
      rescue Web::Fetch::Error => e
        feed.update!(last_scanned_at: Time.current, last_error: e.message)
        []
      end

      def unseen(postings)
        postings.uniq(&:url).reject do |posting|
          user.suggestions.exists?(fingerprint: "#{self.class.slug}/#{fingerprint_for(posting)}")
        end
      end

      def fingerprint_for(posting)
        "posting:#{Digest::SHA256.hexdigest(posting.url)[0, 16]}"
      end

      # The one model call. A failure is recorded and skips this scan —
      # feeds stay marked scanned, postings return as "unseen" next time.
      def picks(profile, postings)
        response = profile.client.chat(
          [ { role: "system", content: SYSTEM_PROMPT },
            { role: "user", content: ranking_prompt(postings) } ],
          json: true
        )
        Array(response["picks"]).filter_map do |pick|
          next unless pick.is_a?(Hash)

          posting = postings[pick["index"].to_i]
          next unless posting

          [ posting, pick["reason"].to_s.strip.presence || "Fits what you've been tracking." ]
        end.uniq { |posting, _reason| posting.url }.first(MAX_PICKS)
      rescue Llm::Error => e
        AppError.record(e, source: "Watcher::JobScout", user: user)
        []
      end

      def ranking_prompt(postings)
        context = Tool::Context.new(user: user, section_slugs: %w[ career hobbies education ])
        parts = []
        if (work = user.work_summary)
          parts << "The user's current work (stated in their profile): #{work}"
        end
        parts << "The user's tracked record:\n#{context.to_prompt}" unless context.empty?
        parts << "Fresh postings:\n" + postings.each_with_index.map { |posting, index| "#{index}. #{posting.line}" }.join("\n")
        parts.join("\n\n")
      end
  end
end
