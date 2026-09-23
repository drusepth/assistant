module Notifications
  # The URL that closes the loop where the notification landed
  # (D-decision-links). A text can say "3 suggestions from your assistant";
  # without this the only way to act on them is to find a browser, sign in,
  # and navigate. One tap should be enough.
  #
  # The token **identifies, it does not authorize**. The page it lands on
  # requires a real session like every other page, so a leaked or
  # carrier-logged URL exposes nothing — which is the D22 lock-screen rule
  # extended to the link the lock screen now carries. That is also why it
  # needs no single-use bookkeeping and no new table: accept and dismiss are
  # idempotent, so a replayed link is harmless, and the only thing the token
  # has to survive is a week in someone's messages.
  class DecisionLink
    PURPOSE = "agent_decision".freeze
    EXPIRES_IN = 7.days

    class << self
      # The payload is packed by hand — "expiry.id-id-id" — rather than
      # handed to Rails' `expires_in:`/`purpose:` metadata, whose JSON
      # wrapper more than doubles the token. That matters for exactly one
      # channel: a text message is bounded at two GSM segments
      # (D-sms-channels) and the URL now spends from that same budget, so
      # every character the token doesn't use is a character the message
      # can. Purpose separation is not lost with the metadata — the
      # verifier's key is already derived from PURPOSE, so a token minted
      # for anything else fails to verify here.
      def token_for(suggestion_ids)
        ids = Array(suggestion_ids).map(&:to_i).reject(&:zero?).uniq.sort
        return nil if ids.empty?

        verifier.generate("#{EXPIRES_IN.from_now.to_i}.#{ids.join("-")}")
      end

      # nil for a tampered, expired, or malformed token — the controller
      # treats all three the same way, since telling them apart would only
      # ever help someone guessing.
      def suggestion_ids(token)
        payload = verifier.verified(token.to_s)
        return nil unless payload.is_a?(String)

        expires_at, ids = payload.split(".", 2)
        return nil if expires_at.to_i <= Time.current.to_i

        ids.to_s.split("-").map(&:to_i).reject(&:zero?).presence
      end

      def url_for(suggestion_ids)
        token = token_for(suggestion_ids)
        return nil if token.nil? || host.blank?

        Rails.application.routes.url_helpers.agent_decision_url(token: token, **url_options)
      end

      # Where the instance lives now has one home (AppHost); this stays as
      # the name the callers and tests already use.
      def host = AppHost.host

      private
        # Built rather than taken from `Rails.application.message_verifier`
        # for two reasons the token's size and shape depend on: url_safe,
        # because it rides in a path segment and the default Base64 alphabet
        # includes "+" and "/"; and the JSON serializer, because Marshal
        # would spend a hundred characters describing a String. The key is
        # still derived from the app's secret, scoped to PURPOSE.
        def verifier
          @verifier ||= ActiveSupport::MessageVerifier.new(
            Rails.application.key_generator.generate_key(PURPOSE),
            url_safe: true, serializer: JSON
          )
        end

        def url_options = AppHost.url_options
    end
  end
end
