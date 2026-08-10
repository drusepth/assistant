require "test_helper"

# The runtime card is the one place the app makes a claim about itself
# rather than about the user's life, so the claim has to stay true. A
# regression here would tell a self-hosting user their data stays on their
# machine while a key ships it to a vendor — pin all three branches.
class DashboardHelperTest < ActionView::TestCase
  include DashboardHelper

  setup do
    # Current.user is delegated from the session, so a session is how you
    # set it — there is no Current.user= writer.
    Current.session = users(:one).sessions.create!
    @profile = model_profiles(:smith)
  end

  teardown { Current.session = nil }

  test "a remote provider is named as remote" do
    assert_match(/\ARemote model — OpenAI/, runtime_line)
    assert_no_match(/Local model/, runtime_line)
  end

  test "a custom endpoint on this machine counts as local" do
    @profile.update!(provider: "custom", base_url: "http://localhost:11434/v1", model: "llama3")

    assert_match(/\ALocal model — /, runtime_line)
  end

  test "a custom endpoint pointed somewhere else is not called local" do
    @profile.update!(provider: "custom", base_url: "https://api.groq.com/openai/v1", model: "llama3")

    assert_match(/\ARemote model — /, runtime_line)
    assert_no_match(/Local model/, runtime_line)
  end

  test "an unconfigured household says so instead of claiming a model" do
    @profile.destroy!
    Current.user.household.reload

    assert_match(/No model configured yet/, runtime_line)
    assert_no_match(/Local model|Remote model/, runtime_line)
  end

  test "the scan half reports the digest stamp, or its absence" do
    Current.user.update!(digest_generated_at: nil)
    assert_match(/first weekly scan still to come/, runtime_line)

    Current.user.update!(digest_generated_at: 3.hours.ago)
    assert_match(/last scan about 3 hours ago/, runtime_line)
  end

  test "a malformed base_url is not mistaken for a local one" do
    @profile.update_columns(provider: "custom", base_url: "not a url")

    assert_no_match(/Local model/, runtime_line)
  end
end
