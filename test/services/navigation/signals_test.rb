require "test_helper"

# The rail's tooltips carry state, not taxonomy: what is behind each door
# right now, or nothing at all. These pin the editorial rules — a date beats
# a count, a quiet row says nothing, and a sealed container says nothing
# either — plus the visibility boundary every count reads through.
class Navigation::SignalsTest < ActiveSupport::TestCase
  setup do
    # Frozen so "today, 3:00 PM" means the same thing at every hour of the
    # suite: half these signals are wall-clock arithmetic.
    travel_to Time.zone.local(2026, 6, 15, 9, 0)
    @user = users(:one)
    @career = sections(:career)
    @health = sections(:health)
    @signals = Navigation::Signals.new(@user)
  end

  # --- life-lens rows ---------------------------------------------------

  test "a section's next event beats its counts" do
    task = @user.tasks.create!(title: "Update résumé")
    task.sections << @career
    event = @user.events.create!(title: "Interview", starts_at: 3.days.from_now.change(hour: 9))
    event.sections << @career

    signal = Navigation::Signals.new(@user).section(@career)

    assert_equal "Interview · #{event.starts_at.strftime("%b %-d")}", signal.body
    assert_nil signal.badge
  end

  test "a section with no dates falls back to what is in flight" do
    task = @user.tasks.create!(title: "Update résumé")
    task.sections << @career
    goal = @user.goals.create!(title: "Get a job")
    goal.sections << @career

    assert_equal "1 open task · 1 project", @signals.section(@career).body
  end

  test "a quiet section says nothing rather than saying it is quiet" do
    assert_nil @signals.section(@health)
  end

  test "overdue work in a section earns the badge" do
    task = @user.tasks.create!(title: "Send the appeal", due_on: 2.days.ago)
    task.sections << @career

    signal = @signals.section(@career)

    assert_equal "Overdue", signal.badge
    assert_equal "1 open task", signal.body
  end

  test "a section signal never counts another household member's private item" do
    task = users(:two).tasks.create!(title: "Their secret")
    task.sections << @career

    assert_nil @signals.section(@career)
  end

  # --- the near dates ---------------------------------------------------

  test "an event today reads as a time, not a date" do
    @user.events.create!(title: "Standup", starts_at: Time.current.change(hour: 15))

    assert_equal "Next: Standup · today, 3:00 PM", @signals.row("Calendar").body
  end

  test "an all-day event tomorrow keeps the day and drops the clock" do
    @user.events.create!(title: "Conference", starts_at: Date.tomorrow.noon, all_day: true)

    assert_equal "Next: Conference · tomorrow", @signals.row("Calendar").body
  end

  # --- the top rows -----------------------------------------------------

  test "Today counts the agenda and flags what is late" do
    @user.tasks.create!(title: "Late one", due_on: 1.day.ago)
    @user.tasks.create!(title: "Due one", due_on: Date.current)
    @user.tasks.create!(title: "Someday")
    @user.events.create!(title: "Standup", starts_at: Time.current.change(hour: 9))

    signal = @signals.row("Today")

    assert_equal "1 overdue · 1 due today · 1 event", signal.body
    assert_equal "Overdue", signal.badge
  end

  test "Tasks reports the board, not the agenda" do
    @user.tasks.create!(title: "Due one", due_on: Date.current)
    2.times { |i| @user.tasks.create!(title: "Someday #{i}") }
    @user.tasks.create!(title: "Done", completed_at: Time.current)

    assert_equal "3 open · 2 unscheduled", @signals.row("Tasks").body
  end

  test "the dashboard counts areas needing attention, not items" do
    late = @user.tasks.create!(title: "Late one", due_on: 1.day.ago)
    late.sections << @career
    today = @user.events.create!(title: "Scan", starts_at: Time.current.change(hour: 11))
    today.sections << @health
    calm = @user.tasks.create!(title: "Someday")
    calm.sections << sections(:money)

    assert_equal "2 areas need attention", @signals.row("Dashboard").body
  end

  test "one area needing attention still reads as English" do
    late = @user.tasks.create!(title: "Late one", due_on: 1.day.ago)
    late.sections << @career

    assert_equal "1 area needs attention", @signals.row("Dashboard").body
  end

  test "conversations names the last one and when it was last touched" do
    old = @user.tool_runs.create!(tool_slug: "check_in", created_at: 1.week.ago)
    old.tool_run_messages.create!(role: "user", content: "hi", created_at: 1.week.ago)
    recent = @user.tool_runs.create!(tool_slug: "task_chat", created_at: 3.days.ago)
    recent.tool_run_messages.create!(role: "user", content: "and again", created_at: 2.hours.ago)

    body = @signals.row("Conversations").body

    assert_match(/\ALast: /, body)
    assert_match(/2 hours ago\z/, body)
    assert_no_match(/#{old.tool.title}/, body)
  end

  # --- the vault --------------------------------------------------------

  test "a vault pile carries its size and what landed this week" do
    @user.notes.create!(body: "Old thought", created_at: 3.weeks.ago)
    @user.notes.create!(body: "Fresh thought")

    assert_equal "2 notes · 1 this week", @signals.row("Notes").body
  end

  test "a vault pile with nothing new says only how big it is" do
    @user.notes.create!(body: "Old thought", created_at: 3.weeks.ago)

    assert_equal "1 note", @signals.row("Notes").body
  end

  test "an empty vault row says nothing" do
    assert_nil @signals.row("Documents")
    assert_nil @signals.row("Photos")
    assert_nil @signals.row("Recipes")
  end

  test "the address book counts contacts and the birthdays about to land" do
    @user.people.create!(name: "Dana", keep_in_touch: true, birthday: Date.current + 2)
    @user.people.create!(name: "Sam", keep_in_touch: true, birthday: Date.current + 90)
    @user.people.create!(name: "Riley")

    assert_equal "3 contacts · 1 birthday this week", @signals.row("Address Book").body
  end

  test "a sealed container never reports what is inside it" do
    assert_nil @signals.row("Passwords")
    assert_nil @signals.row("Diary")
  end

  test "mail reports unread and what wants an answer" do
    account = linked_accounts(:alice_email)
    folder = EmailFolder.create!(user_id: @user.id, linked_account_id: account.id,
      name: "INBOX", role: "inbox", uidvalidity: 1, backfilled_at: Time.current)
    2.times do |i|
      EmailMessage.create!(user_id: @user.id, email_folder: folder, linked_account: account,
        uid: i + 1, message_id: "<unread-#{i}@x>", thread_key: "t#{i}", direction: "inbound",
        seen: false, sent_at: 1.hour.ago)
    end
    EmailMessage.create!(user_id: @user.id, email_folder: folder, linked_account: account,
      uid: 9, message_id: "<action@x>", thread_key: "t9", direction: "inbound",
      seen: true, sent_at: 1.hour.ago, triage: { "category" => "action_needed" })

    signal = @signals.row("Mail")

    assert_equal "2 unread · 1 needs action", signal.body
    assert_equal "Needs action", signal.badge
  end

  # --- the whole quiet rail ---------------------------------------------

  test "a brand-new account draws no state at all" do
    signals = Navigation::Signals.new(users(:outsider))

    [ "Dashboard", "Today", "Calendar", "Tasks", "Conversations", "Address Book",
      "Photos", "Recipes", "Documents", "Notes", "Mail" ].each do |row|
      assert_nil signals.row(row), "#{row} invented something to say"
    end
  end
end
