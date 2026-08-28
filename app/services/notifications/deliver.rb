module Notifications
  # Fans one batched message out to every enabled channel. Payloads carry
  # counts and titles only — bodies stay in the app. Every channel fails
  # independently and silently (a dead webhook must not break push), and
  # an expired push subscription disables itself.
  class Deliver
    TIMEOUT = 5

    def initialize(user, titles:, summary: nil, link: nil)
      @user = user
      @titles = titles
      @summary = summary
      @link = link
    end

    def call
      return if @titles.empty?

      @user.notification_channels.active.find_each do |channel|
        # A metered channel that has spent its day stays quiet rather than
        # billing the user for a chatty scan (D-sms-channels).
        if channel.over_daily_limit?
          Rails.logger.info("notification #{channel.kind}##{channel.id} skipped: daily limit #{channel.daily_limit} reached")
          next
        end

        deliver_to(channel)
        channel.record_send! if channel.daily_limit
      rescue StandardError => error
        Rails.logger.warn("notification #{channel.kind}##{channel.id} failed: #{error.class}: #{error.message}")
      end
    end

    private
      def summary
        return @summary if @summary.present?

        count = @titles.size
        "#{count} #{"suggestion".pluralize(count)} from your assistant: #{@titles.first(3).join("; ")}#{"…" if count > 3}"
      end

      def deliver_to(channel)
        case channel.kind
        when "webhook" then deliver_webhook(channel)
        when "web_push" then deliver_web_push(channel)
        when "email" then deliver_email(channel)
        when "sms" then deliver_sms(channel)
        when "signal" then SignalCli.new(channel).call(phone_text)
        end
      end

      # A phone is the one place where the payload costs money and is kept
      # by someone else, so the D22 summary gets a hard length bound before
      # it leaves — two GSM segments, never four.
      #
      # The decision link (D-decision-links) spends from that same budget
      # rather than extending it: the bound exists to cap what a carrier
      # keeps and what a message costs, and neither cares which half of the
      # text is a URL. So the summary is trimmed to fit around the link, and
      # the link goes in whole — a truncated URL is worse than no URL.
      def phone_text
        return summary.truncate(NotificationChannel::TEXT_LIMIT) if @link.blank?

        room = NotificationChannel::TEXT_LIMIT - @link.length - 1
        "#{summary.truncate([ room, 40 ].max)} #{@link}"
      end

      def deliver_sms(channel)
        transport = Sms.for(channel)
        raise DeliveryError, "unknown SMS provider #{channel.sms_provider.inspect}" if transport.nil?

        transport.call(phone_text)
      end

      def deliver_webhook(channel)
        uri = URI(channel.config["url"])
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        # ntfy and friends read Title/plain body; everything else gets JSON.
        request["Title"] = "Assistant"
        request.body = { title: "Assistant", message: summary, count: @titles.size, titles: @titles,
                         url: @link }.compact.to_json
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.request(request) }
      end

      def deliver_web_push(channel)
        subscription = channel.config["subscription"]
        WebPush.payload_send(
          # The service worker opens `url` when the notification is tapped,
          # which is the same one-tap loop the phone channels get.
          message: { title: "Assistant", body: summary, url: @link }.compact.to_json,
          endpoint: subscription["endpoint"],
          p256dh: subscription.dig("keys", "p256dh"),
          auth: subscription.dig("keys", "auth"),
          vapid: {
            subject: "mailto:assistant@localhost",
            public_key: Rails.application.config.x.web_push.public_key,
            private_key: Rails.application.config.x.web_push.private_key
          }
        )
      rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
        channel.update!(enabled: false)
      end

      def deliver_email(channel)
        NotificationsMailer.suggestions(channel.config["address"], summary, @titles, @link).deliver_now
      end
  end
end
