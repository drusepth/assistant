module Diary
  # Consecutive days written, counted back from today — the one number that
  # makes a writing habit visible. Yesterday still counts as an unbroken
  # streak, because a diary written in the evening shouldn't punish someone
  # for opening the page before they've written today's.
  class Streak
    def initialize(dates)
      @dates = dates.map { |date| date.to_date }.to_set
    end

    def length
      day = if @dates.include?(Date.current) then Date.current
      elsif @dates.include?(Date.yesterday) then Date.yesterday
      else return 0
      end

      count = 0
      while @dates.include?(day)
        count += 1
        day -= 1
      end
      count
    end
  end
end
