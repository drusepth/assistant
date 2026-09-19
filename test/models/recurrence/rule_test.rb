require "test_helper"

# D-standing-reminders: one recurrence grammar. The property that matters
# most is the last group — the next occurrence is a pure function of the
# current one, because a standing reminder remembers nothing else.
class Recurrence::RuleTest < ActiveSupport::TestCase
  CHICAGO = ActiveSupport::TimeZone["America/Chicago"]

  def rule(text) = Recurrence::Rule.parse(text)
  def at(*parts) = CHICAGO.local(*parts)
  def first(text, start, n) = rule(text).occurrences(start).first(n)

  test "parses, canonicalizes, and knows what it can expand" do
    r = rule("byday=TH;freq=WEEKLY")
    assert_equal "WEEKLY", r.freq
    assert_equal [ "TH" ], r.weekdays
    assert_equal "FREQ=WEEKLY;BYDAY=TH", r.to_s
    assert r.supported?
    assert r.standing?

    assert_nil rule("")
    assert_not rule("FREQ=HOURLY;COUNT=3").supported?
    assert_not rule("FREQ=YEARLY;BYMONTH=3;BYDAY=2SU").supported?, "ordinal BYDAY is monthly-only"
    assert_not rule("FREQ=WEEKLY;BYDAY=XX").supported?
    assert_not rule("FREQ=WEEKLY;COUNT=4").standing?, "COUNT counts from a start a reminder no longer knows"
  end

  test "daily and yearly step from the start" do
    assert_equal [ at(2026, 9, 19, 20), at(2026, 9, 20, 20), at(2026, 9, 21, 20) ],
      first("FREQ=DAILY", at(2026, 9, 19, 20), 3)
    assert_equal [ at(2026, 9, 19, 9), at(2028, 9, 19, 9) ],
      first("FREQ=YEARLY;INTERVAL=2", at(2026, 9, 19, 9), 2)
  end

  test "weekly expands inside the calendar week, from the start onward" do
    # Sat Sep 19 2026: the Thursday of that week is already past, so the
    # first Thursday is the 24th.
    assert_equal [ at(2026, 9, 24, 20), at(2026, 10, 1, 20) ],
      first("FREQ=WEEKLY;BYDAY=TH", at(2026, 9, 19, 20), 2)

    # Wed Sep 16: Fri of the same week, then Mon and Fri of the next.
    assert_equal [ at(2026, 9, 18, 8), at(2026, 9, 21, 8), at(2026, 9, 25, 8) ],
      first("FREQ=WEEKLY;BYDAY=MO,FR", at(2026, 9, 16, 8), 3)

    # No BYDAY: the start's own weekday.
    assert_equal [ at(2026, 9, 16, 8), at(2026, 9, 23, 8) ], first("FREQ=WEEKLY", at(2026, 9, 16, 8), 2)
  end

  test "every 2 weeks skips a calendar week between occurrences" do
    # Wed Sep 16: Fri 18, then the week of Sep 28 (Mon 28, Fri Oct 2).
    assert_equal [ at(2026, 9, 18, 8), at(2026, 9, 28, 8), at(2026, 10, 2, 8) ],
      first("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR", at(2026, 9, 16, 8), 3)
  end

  test "monthly on the 31st skips the months without one" do
    assert_equal [ at(2026, 1, 31, 9), at(2026, 3, 31, 9), at(2026, 5, 31, 9) ],
      first("FREQ=MONTHLY;BYMONTHDAY=31", at(2026, 1, 31, 9), 3)
    assert_equal [ at(2026, 1, 31, 9), at(2026, 3, 31, 9) ], first("FREQ=MONTHLY", at(2026, 1, 31, 9), 2)
  end

  test "monthly on an ordinal weekday" do
    # Second Tuesday: Sep 8 2026 is one, then Oct 13, Nov 10.
    assert_equal [ at(2026, 9, 8, 19), at(2026, 10, 13, 19), at(2026, 11, 10, 19) ],
      first("FREQ=MONTHLY;BYDAY=2TU", at(2026, 9, 8, 19), 3)
    assert_equal [ at(2026, 9, 25, 19), at(2026, 10, 30, 19) ],
      first("FREQ=MONTHLY;BYDAY=-1FR", at(2026, 9, 25, 19), 2)
  end

  test "keeps the wall-clock time across a DST change" do
    # Chicago falls back Nov 1 2026.
    times = first("FREQ=WEEKLY;BYDAY=SU", at(2026, 10, 25, 20), 2)
    assert_equal [ 20, 20 ], times.map(&:hour)
    assert_equal at(2026, 11, 1, 20), times.last
  end

  test "COUNT and UNTIL end the series" do
    assert_equal 3, rule("FREQ=DAILY;COUNT=3").occurrences(at(2026, 9, 19, 9)).count
    # UNTIL as a date is inclusive of that whole day.
    assert_equal [ at(2026, 9, 19, 9), at(2026, 9, 20, 9) ],
      rule("FREQ=DAILY;UNTIL=20260920").occurrences(at(2026, 9, 19, 9)).to_a
    assert_equal [ at(2026, 9, 19, 9) ],
      rule("FREQ=DAILY;UNTIL=20260920T130000Z").occurrences(at(2026, 9, 19, 9)).to_a
  end

  test "next_after walks forward from the current occurrence" do
    r = rule("FREQ=WEEKLY;BYDAY=TH")
    thursday = at(2026, 9, 24, 20)

    assert_equal at(2026, 10, 1, 20), r.next_after(thursday, current: thursday)
    # Three Thursdays missed: the next one, not a burst of the missed ones.
    assert_equal at(2026, 10, 22, 20), r.next_after(at(2026, 10, 16, 12), current: thursday)
    # The current moment itself, when it still lies ahead.
    assert_equal thursday, r.next_after(at(2026, 9, 19, 12), current: thursday)
    assert_nil rule("FREQ=DAILY;UNTIL=20260920").next_after(at(2026, 9, 21), current: at(2026, 9, 20, 9))
  end

  test "the next occurrence is the same whichever occurrence you compute it from" do
    %w[ FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR FREQ=WEEKLY;INTERVAL=3;BYDAY=TU FREQ=MONTHLY;BYMONTHDAY=31
        FREQ=MONTHLY;BYDAY=-1FR FREQ=DAILY;INTERVAL=3 FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR ].each do |text|
      r = rule(text)
      sequence = r.occurrences(at(2026, 9, 16, 8)).first(8)

      sequence.each_cons(2) do |current, following|
        assert_equal following, r.next_after(current, current: current), "#{text}: from #{current}"
      end
    end
  end

  test "describes itself in prose" do
    assert_equal "weekly on Thursday", rule("FREQ=WEEKLY;BYDAY=TH").describe
    assert_equal "every 2 weeks on Monday, Friday", rule("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR").describe
    assert_equal "every weekday", rule("FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR").describe
    assert_equal "monthly on the 19th", rule("FREQ=MONTHLY;BYMONTHDAY=19").describe
    assert_equal "monthly on the last Friday", rule("FREQ=MONTHLY;BYDAY=-1FR").describe
    assert_equal "daily", rule("FREQ=DAILY").describe
    assert_equal "weekly on Tuesday, 4 times", rule("FREQ=WEEKLY;BYDAY=TU;COUNT=4").describe
    assert_equal "yearly until Sep 20, 2027", rule("FREQ=YEARLY;UNTIL=20270920").describe
  end
end
