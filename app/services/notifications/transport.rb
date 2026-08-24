module Notifications
  # Shared plumbing for the channels that reach a phone: one destination,
  # one short text, credentials read through the channel (which knows
  # whether a given field lives in plain config or the encrypted half).
  #
  # Subclasses implement `call(text)` and raise DeliveryError on anything
  # the user would need to fix.
  class Transport
    TIMEOUT = 5

    def initialize(channel)
      @channel = channel
    end

    def call(text)
      raise NotImplementedError
    end

    private
      attr_reader :channel

      def to = channel.config["to"]
      def from = channel.config["from"]
      def setting(key) = channel.setting(key)

      # Anything but a 2xx is a delivery failure worth naming — carriers
      # answer 401 for a stale token and 400 for an unregistered number,
      # and both look like success to a caller that ignores the response.
      def post(uri, request)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.request(request) }

        unless response.is_a?(Net::HTTPSuccess)
          raise DeliveryError, "#{uri.host} answered #{response.code}: #{response.body.to_s.truncate(200)}"
        end

        response
      end
  end
end
