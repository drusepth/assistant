module Notifications
  module Sms
    # Twilio's Programmable Messaging API: a form POST with basic auth, so
    # no gem — the same Net::HTTP the webhook channel already uses.
    #
    # US traffic needs A2P 10DLC registration on Twilio's side before
    # anything sends; unregistered sends come back as a 400 here, which is
    # why `post` reports the provider's own message rather than swallowing it.
    class Twilio < Transport
      API_HOST = "https://api.twilio.com".freeze

      def call(text)
        account_sid = setting("account_sid")
        uri = URI("#{API_HOST}/2010-04-01/Accounts/#{account_sid}/Messages.json")

        request = Net::HTTP::Post.new(uri)
        request.basic_auth(account_sid, setting("auth_token"))
        request.set_form_data(form(text))

        post(uri, request)
      end

      private
        def form(text)
          # A Messaging Service (MG…) is a pool of numbers rather than one
          # number, and Twilio takes it in a different field.
          sender = setting("from").to_s
          origin = sender.start_with?("MG") ? { "MessagingServiceSid" => sender } : { "From" => sender }

          origin.merge("To" => to, "Body" => text)
        end
    end
  end
end
