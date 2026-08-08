module Watcher
  # Memories, deterministically (D31/W5): photos taken around this date in
  # a past year get one look-back nudge. Sectionless, so it runs on the
  # Quiet cadence; fingerprinted per (past year, current year) so a
  # dismissal quiets that anniversary until next year.
  class OnThisDay < Base
    WINDOW = 3 # days either side of today's date

    def scan
      anniversary_years.each do |year|
        anniversary = anniversary_for(year)
        count = user.photos.where(
          taken_at: (anniversary - WINDOW.days).beginning_of_day..(anniversary + WINDOW.days).end_of_day
        ).count
        next if count.zero?

        years_ago = Date.current.year - year
        propose(
          fingerprint: "#{year}-#{Date.current.year}",
          kind: :insight,
          title: "On this day: #{years_ago} #{"year".pluralize(years_ago)} ago",
          body: "You took #{count} #{"photo".pluralize(count)} around this day in #{year}. Worth a look back.",
          action: { "path" => Rails.application.routes.url_helpers.photos_path(year: year) }
        )
      end
    end

    private
      def anniversary_years
        user.photos.distinct.pluck(Arel.sql("strftime('%Y', taken_at)"))
          .map(&:to_i).select { |year| year < Date.current.year }.sort
      end

      def anniversary_for(year)
        Date.current.change(year: year)
      rescue Date::Error
        Date.new(year, 2, 28) # Feb 29 in a non-leap past year
      end
  end
end
