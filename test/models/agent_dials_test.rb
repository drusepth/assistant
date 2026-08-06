require "test_helper"

# The D20 dials (M3.2): Off / Quiet (default) / Active, per section,
# honored by the scan cadences.
class AgentDialsTest < ActiveJob::TestCase
  setup do
    @user = users(:one)
    stub_request(:post, "https://api.openai.com/v1/chat/completions").to_return(status: 500, body: "down")
  end

  test "the dial defaults to quiet and follows the stored level" do
    assert_equal "quiet", @user.agent_level_for(sections(:health))

    @user.user_sections.create!(section: sections(:health), agent_level: "active")
    assert_equal "active", @user.agent_level_for(sections(:health))
  end

  test "a disabled section is implicitly off, whatever its dial says" do
    @user.user_sections.create!(section: sections(:health), enabled: false, agent_level: "active")

    assert_equal "off", @user.agent_level_for(sections(:health))
  end

  test "an off dial silences the section's watcher on every cadence" do
    @user.user_sections.create!(section: sections(:health), agent_level: "off")

    AgentScanJob.perform_now(@user, cadence: "weekly")
    AgentScanJob.perform_now(@user, cadence: "daily")

    assert_empty @user.suggestions.where(watcher_slug: "checkup_cadence")
  end

  test "the daily cadence only runs watchers on active sections" do
    AgentScanJob.perform_now(@user, cadence: "daily")
    assert_empty @user.suggestions, "quiet sections are weekly-only"

    @user.user_sections.create!(section: sections(:health), agent_level: "active")
    AgentScanJob.perform_now(@user, cadence: "daily")
    assert_equal 1, @user.suggestions.where(watcher_slug: "checkup_cadence").count
  end

  test "the weekly cadence covers quiet and active sections alike" do
    AgentScanJob.perform_now(@user, cadence: "weekly")

    assert_equal 1, @user.suggestions.where(watcher_slug: "checkup_cadence").count
  end

  test "settings persist the dial per section" do
    sign_in_and_update = lambda do |level|
      { enabled_section_ids: Section.top_level.ids, agent_levels: { sections(:health).id.to_s => level } }
    end

    integration = ActionDispatch::Integration::Session.new(Rails.application)
    integration.post "/session", params: { email_address: @user.email_address, password: "password" }
    integration.patch "/settings", params: sign_in_and_update.call("active")

    assert_equal "active", @user.reload.agent_level_for(sections(:health))
  end
end
