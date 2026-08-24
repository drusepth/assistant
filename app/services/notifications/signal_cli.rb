module Notifications
  # signal-cli-rest-api (D-sms-channels): a container the household runs,
  # registered to their own Signal number.
  #
  # Strictly better than SMS wherever the recipient has Signal — free,
  # end-to-end encrypted, and no carrier keeps a copy of what the
  # assistant said. It stays under the same D22 payload rule anyway: the
  # channel is private, the lock screen it lands on is not.
  #
  # https://github.com/bbernhard/signal-cli-rest-api
  class SignalCli < Transport
    def call(text)
      uri = URI.join("#{channel.config["url"].to_s.chomp("/")}/", "v2/send")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      # The API ships without auth; most people put it behind a reverse
      # proxy, so honor basic-auth credentials when they set them.
      username = setting("username")
      request.basic_auth(username, setting("password")) if username.present?
      request.body = { message: text, number: from, recipients: [ to ] }.to_json

      post(uri, request)
    end
  end
end
