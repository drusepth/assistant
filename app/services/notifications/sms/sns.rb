module Notifications
  module Sms
    # Amazon SNS publishes straight to a phone number — no number to rent,
    # no inbound, one API call.
    #
    # The request is signed with Signature Version 4 by hand (~30 lines of
    # HMAC below) rather than by pulling in the AWS SDK: this is the only
    # thing in the app that talks to AWS, and a self-hosted install should
    # not carry a transitive dependency tree for one POST.
    class Sns < Transport
      VERSION = "2010-03-31".freeze
      ALGORITHM = "AWS4-HMAC-SHA256".freeze
      SERVICE = "sns".freeze

      def call(text)
        region = setting("region")
        host = "sns.#{region}.amazonaws.com"
        uri = URI("https://#{host}/")
        body = URI.encode_www_form(params(text))

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8"
        request["Host"] = host
        request.body = body
        sign(request, host: host, region: region, body: body)

        post(uri, request)
      end

      private
        def params(text)
          params = {
            "Action" => "Publish",
            "Version" => VERSION,
            "PhoneNumber" => to,
            "Message" => text,
            # Transactional buys the higher-reliability route. These are
            # alerts the user asked for, not marketing.
            "MessageAttributes.entry.1.Name" => "AWS.SNS.SMS.SMSType",
            "MessageAttributes.entry.1.Value.DataType" => "String",
            "MessageAttributes.entry.1.Value.StringValue" => "Transactional"
          }

          sender_id = setting("sender_id")
          if sender_id.present?
            params["MessageAttributes.entry.2.Name"] = "AWS.SNS.SMS.SenderID"
            params["MessageAttributes.entry.2.Value.DataType"] = "String"
            params["MessageAttributes.entry.2.Value.StringValue"] = sender_id
          end

          params
        end

        # https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv4-signing-elements.html
        def sign(request, host:, region:, body:)
          now = Time.now.utc
          amz_date = now.strftime("%Y%m%dT%H%M%SZ")
          date = now.strftime("%Y%m%d")
          request["X-Amz-Date"] = amz_date

          signed_headers = "content-type;host;x-amz-date"
          canonical_headers = "content-type:#{request["Content-Type"]}\nhost:#{host}\nx-amz-date:#{amz_date}\n"
          # Method, path, query, headers, signed-header list, payload hash —
          # the trailing newline on canonical_headers is what produces the
          # blank line the spec requires between the two.
          canonical_request = [ "POST", "/", "", canonical_headers, signed_headers, hexdigest(body) ].join("\n")

          scope = "#{date}/#{region}/#{SERVICE}/aws4_request"
          string_to_sign = [ ALGORITHM, amz_date, scope, hexdigest(canonical_request) ].join("\n")
          signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key(date, region), string_to_sign)

          request["Authorization"] =
            "#{ALGORITHM} Credential=#{setting("access_key_id")}/#{scope}, " \
            "SignedHeaders=#{signed_headers}, Signature=#{signature}"
        end

        # The secret is stretched over date, region and service so a leaked
        # signing key is worth one day in one region.
        def signing_key(date, region)
          key = hmac("AWS4#{setting("secret_access_key")}", date)
          key = hmac(key, region)
          key = hmac(key, SERVICE)
          hmac(key, "aws4_request")
        end

        def hmac(key, data) = OpenSSL::HMAC.digest("SHA256", key, data)
        def hexdigest(value) = OpenSSL::Digest::SHA256.hexdigest(value)
    end
  end
end
