module Notifications
  # A channel could not hand the message off. Notifications::Deliver
  # rescues every channel independently (D22), so this exists to say *why*
  # in the log rather than to be caught: a 401 from Twilio and an unwritable
  # gammu outbox are the two failures a self-hoster actually has to debug,
  # and both are silent otherwise.
  class DeliveryError < StandardError; end
end
