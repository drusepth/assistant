module Watcher
  # The wage-theft tripwire (docs/CAREER.md §4): when the user's newest
  # analyzed pay stub fails the PayStubAudit arithmetic — gross short of
  # hours × rate, overtime missing, a rate drop — say so, with the evidence,
  # and offer the stub-check tool. Deterministic math over extracted facts;
  # no time bucket on the fingerprint, because a stub's anomaly doesn't
  # expire — one nudge per stub, dismissed stays gone.
  class StubAnomaly < Base
    self.section_slugs = %w[ career money ]

    def scan
      stub = latest_stub
      return unless stub

      audit = Career::PayStubAudit.new(stub)
      return unless audit.concerning?

      propose(
        fingerprint: "doc:#{stub.document.id}",
        title: "Your pay stub “#{stub.document.title}” doesn't add up",
        body: audit.concerning_findings.first,
        kind: :heads_up,
        action: { "tool" => { "slug" => "check_pay_stub",
                              "inputs" => { "document_id" => stub.document.id.to_s } } }
      )
    end

    private
      def latest_stub
        Career::PayStub.scope(user)
          .filter_map { |document| Career::PayStub.for(document) }
          .max_by(&:logged_on)
      end
  end
end
