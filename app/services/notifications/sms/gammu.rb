module Notifications
  module Sms
    # gammu-smsd with a GSM modem and the household's own SIM: no account,
    # no per-message fee, no third party in the path at all. The most
    # mission-true way to get a text, and the only one that keeps working
    # when the instance has no outbound internet.
    #
    # Delivery is a file drop into the daemon's FILES-backend outbox —
    # no shelling out to gammu-smsd-inject (which would need the binary in
    # this container and would put a user-supplied number on a command
    # line), and no second database connection for the SQL backend. Mount
    # the outbox directory into the app and that is the whole integration.
    #
    # https://docs.gammu.org/smsd/files.html
    class Gammu < Transport
      def call(text)
        outbox = Pathname.new(setting("outbox_path").to_s)
        raise DeliveryError, "gammu outbox #{outbox} is not a directory" unless outbox.directory?
        raise DeliveryError, "gammu outbox #{outbox} is not writable" unless outbox.writable?

        # gammu-smsd scans the outbox continuously, so a file written in
        # place can be picked up half-written. Stage it under a name the
        # scanner ignores and rename — atomic within one filesystem.
        staged = outbox.join(".assistant-#{SecureRandom.hex(8)}.tmp")
        staged.write(text)
        staged.rename(outbox.join(filename).to_s)
      end

      private
        # OUT<priority><date>_<time>_<serial>_<number>_<note>.txt — the
        # fully specified form. Messages go out in filename order, so the
        # timestamp leads; priority G leaves room for anything the box
        # queues ahead of us (A is highest), and the serial only has to
        # break ties inside one second.
        def filename
          stamp = Time.now.utc.strftime("%Y%m%d_%H%M%S")
          serial = format("%06d", SecureRandom.random_number(1_000_000))

          "OUTG#{stamp}_#{serial}_#{to}_assistant.txt"
        end
    end
  end
end
