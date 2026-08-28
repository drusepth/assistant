require "test_helper"

# D-decision-links: the token identifies, the session authorizes. Most of
# what matters here is what the token *cannot* do.
class DecisionLinkTest < ActiveSupport::TestCase
  test "a token round-trips the batch it was minted for" do
    token = Notifications::DecisionLink.token_for([ 12, 345, 6789 ])

    assert_equal [ 12, 345, 6789 ], Notifications::DecisionLink.suggestion_ids(token)
  end

  test "the token is url-safe and short enough to ride in a text message" do
    token = Notifications::DecisionLink.token_for([ 1234, 5678, 9012 ])
    url = "https://assistant.example.org/assistant/decisions/#{token}"

    assert_match(/\A[A-Za-z0-9_\-.=]+\z/, token, "it rides in a path segment")
    assert url.length < NotificationChannel::TEXT_LIMIT / 2,
      "the URL spends from the two-segment SMS budget, so it has to leave room for the message"
  end

  test "a tampered token is refused" do
    token = Notifications::DecisionLink.token_for([ 12 ])
    body, signature = token.split("--")

    assert_nil Notifications::DecisionLink.suggestion_ids("#{body}--#{signature.reverse}")
    assert_nil Notifications::DecisionLink.suggestion_ids("nonsense")
    assert_nil Notifications::DecisionLink.suggestion_ids("")
  end

  test "an expired token is refused" do
    token = travel_to(8.days.ago) { Notifications::DecisionLink.token_for([ 12 ]) }

    assert_nil Notifications::DecisionLink.suggestion_ids(token)
  end

  test "a token minted for another purpose does not verify here" do
    other = ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key("something_else"), url_safe: true, serializer: JSON
    )

    assert_nil Notifications::DecisionLink.suggestion_ids(other.generate("#{1.day.from_now.to_i}.12"))
  end

  test "an instance whose address nobody configured sends no link, rather than a link to nowhere" do
    original = Rails.application.config.action_mailer.default_url_options
    Rails.application.config.action_mailer.default_url_options = {}

    assert_nil Notifications::DecisionLink.url_for([ 12 ])
  ensure
    Rails.application.config.action_mailer.default_url_options = original
  end

  test "APP_HOST is what a self-hosted instance answers with" do
    ENV["APP_HOST"] = "https://assistant.example.org"

    url = Notifications::DecisionLink.url_for([ 12 ])

    assert url.start_with?("https://assistant.example.org/assistant/decisions/"), url
    assert_equal [ 12 ], Notifications::DecisionLink.suggestion_ids(url.split("/").last)
  ensure
    ENV.delete("APP_HOST")
  end

  test "an empty batch has no link" do
    assert_nil Notifications::DecisionLink.token_for([])
    assert_nil Notifications::DecisionLink.url_for([])
  end
end
