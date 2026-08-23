module Notifications
  # Text messages (D-sms-channels). One class per provider, all behind the
  # same Transport interface, so which carrier a household uses is a
  # settings choice rather than an integration — the same stance the model
  # layer takes toward model providers.
  module Sms
    # nil for a channel whose provider left the registry (a downgrade, a
    # typo in seeded data); Deliver treats that as a channel that can't
    # send rather than raising through the fan-out.
    def self.for(channel)
      service = channel.sms_provider_settings[:service]
      service&.constantize&.new(channel)
    end
  end
end
