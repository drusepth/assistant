module Sections
  module Panels
    # The Career lead panel (D-career-signal, docs/CAREER.md): the section
    # asks for the signal its tools and watchers run on — the win log and
    # the comp timeline — and lists the job-scout feeds. Everything here is
    # ordinary primitives read back, so the panel holds no state of its own
    # beyond the queries.
    class Career < Panel
      RECENT_WINS = 3

      def recent_wins
        @recent_wins ||= ::Career::WinLog.scope(viewer).order(created_at: :desc).limit(RECENT_WINS)
      end

      def last_comp_change_on
        return @last_comp_change_on if defined?(@last_comp_change_on)

        @last_comp_change_on = ::Career::CompChange.latest_on(viewer)
      end

      def months_since_comp_change
        return nil unless last_comp_change_on

        (Date.current.year * 12 + Date.current.month) -
          (last_comp_change_on.year * 12 + last_comp_change_on.month)
      end

      def job_feeds
        @job_feeds ||= viewer.job_feeds.order(:created_at)
      end
    end
  end
end
