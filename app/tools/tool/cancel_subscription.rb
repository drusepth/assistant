module Tool
  # PRODUCT.md's "cancel this for me" drafting: a cancellation letter plus a
  # short phone script, with a follow-up to verify the charges actually
  # stopped — the step everyone forgets.
  class CancelSubscription < Base
    self.title = "Cancel a subscription"
    self.description = "A cancellation letter and phone script, plus a reminder to check the charge stopped."
    self.section_slugs = %w[ subscriptions ]
    self.kind = :draft

    input :service, required: true,
      label: "Which service?"
    input :reason,
      label: "Why are you cancelling?",
      hint: "Optional — helps push back if they offer retention deals."

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the subscription-cancellation feature of a private, self-hosted
      life assistant. The draft has two parts, clearly separated: a short formal
      cancellation letter/email, and a brief phone script for the same request.
      Both must: state the cancellation plainly with no ambiguity; request
      written confirmation, the effective date, and that no further charges be
      made; decline retention offers politely but firmly (use the user's reason
      if given); mention refund of any pre-paid unused period where plausible.
      follow_ups: send or call, and verify on the next billing date that the
      charge stopped.
      #{DRAFT_FORMAT}
    PROMPT

    private
      def messages
        [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_prompt }
        ]
      end

      def user_prompt
        parts = [ "Today's date: #{Date.current.iso8601}" ]
        parts << "The user's name, for the signature: #{user.name}"
        parts << "Service to cancel: #{inputs[:service]}"
        parts << "Why: #{inputs[:reason]}" if inputs[:reason].present?
        parts.join("\n\n")
      end

      def fallback_title = "Cancel #{inputs[:service]}"
  end
end
