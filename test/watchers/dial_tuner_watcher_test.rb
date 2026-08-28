require "test_helper"

# D-agent-earned-dials: the Active dial is offered, never defaulted — and
# going quieter is offered on the same terms. Both offers are model-free,
# and the dial only ever moves on an accept.
class DialTunerWatcherTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @health = sections(:health)
    dial(:quiet)
  end

  test "a section whose suggestions get used earns an offer to go Active" do
    3.times { |n| decided(:accepted, n) }

    suggestion = scan.sole

    assert_equal "dial_tuner/upgrade/health", suggestion.fingerprint
    assert_equal "insight", suggestion.kind
    assert_equal({ "section" => "health", "level" => "active" }, suggestion.action["agent_level"])
    assert_equal [ @health ], suggestion.sections.to_a, "it surfaces where the question makes sense"
  end

  test "accepting moves the dial and nothing else" do
    3.times { |n| decided(:accepted, n) }
    suggestion = scan.sole

    assert_no_difference [ -> { @user.tasks.count }, -> { @user.events.count } ] do
      suggestion.accept!
    end

    assert_equal "active", @user.reload.agent_level_for(@health)
  end

  test "an unused section earns nothing" do
    2.times { |n| decided(:accepted, n) }

    assert_empty scan, "two is not a habit"
  end

  test "the offer is made once, ever" do
    3.times { |n| decided(:accepted, n) }
    scan.sole.dismiss!

    assert_empty scan, "a dismissal is a permanent answer to this one"
  end

  test "a section dismissed on sight earns an offer to go quieter" do
    Watcher::DialTuner::IGNORED_RUN.times { |n| decided(:dismissed, n) }

    suggestion = scan.sole

    assert_equal "dial_tuner/quieter/health/#{Date.current.year}", suggestion.fingerprint
    assert_equal({ "section" => "health", "level" => "off" }, suggestion.action["agent_level"])

    suggestion.accept!
    assert_equal "off", @user.reload.agent_level_for(@health)
  end

  test "an Active section goes down one step, not straight off" do
    dial(:active)
    Watcher::DialTuner::IGNORED_RUN.times { |n| decided(:dismissed, n) }

    scan.sole.accept!

    assert_equal "quiet", @user.reload.agent_level_for(@health)
  end

  test "dismissals after an acceptance are someone using the feature, not tiring of it" do
    decided(:accepted, 0)
    Watcher::DialTuner::IGNORED_RUN.times { |n| decided(:dismissed, n + 1) }

    assert_empty scan.select { |s| s.fingerprint.include?("quieter") }
  end

  test "suggestions the world retired don't count as ignored" do
    # `resolved` is the app being right, not being unwanted.
    Watcher::DialTuner::IGNORED_RUN.times { |n| decided(:resolved, n) }

    assert_empty scan
  end

  test "the tuner's own suggestions never feed its counts" do
    # An ignored offer to be quieter must not become evidence for going
    # quieter still.
    Watcher::DialTuner::IGNORED_RUN.times do |n|
      suggestion = @user.suggestions.create!(watcher_slug: "dial_tuner", fingerprint: "dial_tuner/x#{n}",
        title: "Should I pipe down?", status: :dismissed)
      suggestion.sections = [ @health ]
    end

    assert_empty scan
  end

  test "an Off section is left alone" do
    dial(:off)
    3.times { |n| decided(:accepted, n) }

    assert_empty scan, "Off is a deliberate choice, not one to relitigate"
  end

  test "the offer retires once the dial has moved in Settings" do
    3.times { |n| decided(:accepted, n) }
    suggestion = scan.sole

    dial(:active)

    assert Watcher::DialTuner.new(@user).resolved?(suggestion),
      "the question answered itself; asking again would be the app not noticing"
  end

  private
    def dial(level)
      @user.user_sections.find_or_initialize_by(section: @health).update!(agent_level: level, enabled: true)
    end

    def decided(status, index)
      suggestion = @user.suggestions.create!(
        watcher_slug: "checkup_cadence", fingerprint: "checkup_cadence/#{status}#{index}",
        title: "Book something", status: status, created_at: (index + 1).days.ago
      )
      suggestion.sections = [ @health ]
      suggestion
    end

    def scan
      watcher = Watcher::DialTuner.new(@user)
      watcher.scan
      watcher.proposals
    end
end
