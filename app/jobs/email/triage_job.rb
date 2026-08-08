# Labels a batch of mirrored messages (EMAIL_PLAN.md §6). The economics
# rules live here: deterministic pre-emption first (bulk mail never spends
# a token; sender rules join in E3), then the model — only when one is
# configured and the link's AI toggle is on, and only within the per-link
# daily budget. Over budget, the remainder stays untriaged until tomorrow
# and the shortfall is written down for /admin (D23), never swallowed.
class Email::TriageJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  # Mailbox-flood protection, not rationing: model-labeled messages per
  # link per day. A cattr so tests can lower it.
  cattr_accessor :daily_model_budget, default: 400

  def perform(account, message_ids)
    return if account.paused?
    messages = EmailMessage.where(linked_account_id: account.id, id: message_ids, triaged_at: nil)
      .order(:id).to_a
    return if messages.empty?

    rules = EmailSenderRule.for(account.user) if account.user
    rules ||= {}

    precomputed, remaining = messages.partition { |message| code_label(message, rules) }
    precomputed.each { |message| apply_code_label(message, rules) }

    model_pass(account, remaining) if remaining.any?
    apply_vip_floor(remaining, rules)

    surface_deadlines(account)

    # The immediate path (E3): only when the dial is on; the alert job
    # re-checks everything — this is just the handoff.
    if account.setting(:alerts) == true && remaining.any?
      Email::UrgentAlertJob.perform_later(account, remaining.map(&:id))
    end
  end

  private
    # Deterministic pre-emption (EMAIL_PLAN.md §6): bulk mail and muted
    # senders are labeled by code and never spend a token.
    def code_label(message, rules)
      return "noise" if message.bulk?
      "noise" if rules[message.from_email.to_s] == "mute"
    end

    def apply_code_label(message, rules)
      message.update!(
        triage: { "category" => code_label(message, rules), "importance" => 0, "by" => "code" },
        importance: 0, triaged_at: Time.current)
    end

    # A vip verdict the user taught outranks the model's: importance never
    # lands below the floor for senders marked "More like this".
    def apply_vip_floor(messages, rules)
      messages.each do |message|
        next unless rules[message.from_email.to_s] == "vip"
        message.reload
        next if message.triaged_at.nil? || message.importance.to_i >= EmailSenderRule::VIP_IMPORTANCE_FLOOR

        message.update!(
          importance: EmailSenderRule::VIP_IMPORTANCE_FLOOR,
          triage: (message.triage || {}).merge("vip_floor" => true))
      end
    end

    def model_pass(account, messages)
      profile = account.user&.household&.model_profile
      return unless profile&.configured?
      return if account.setting(:ai_processing) == false

      affordable = messages.first(budget_remaining(account))
      overflow = messages.size - affordable.size

      Email::Triage.new(user: account.user, profile: profile).call(affordable) if affordable.any?

      if overflow.positive?
        AppError.record(StandardError.new("Daily triage budget reached — #{overflow} messages left unlabeled until tomorrow."),
          source: "email_triage", user: account.user, context: { linked_account_id: account.id })
      end
    rescue Llm::Error => e
      raise if will_retry?(e)
      # Final attempt: triage is garnish (D16) — the mail stays browsable,
      # just unlabeled. Visible to the operator, silent for the user.
      AppError.record(e, source: "email_triage", user: account.user, context: { linked_account_id: account.id })
    end

    def budget_remaining(account)
      spent = EmailMessage.where(linked_account_id: account.id)
        .where(triaged_at: Time.current.all_day)
        .where("json_extract(triage, '$.by') = 'model'").count
      [ daily_model_budget - spent, 0 ].max
    end

    # Freshly labeled deadlines become pending suggestions right away
    # rather than waiting for the weekly scan — same watcher either way
    # (D20: the suggestions table is the only write surface).
    def surface_deadlines(account)
      user = account.user or return
      Watcher::EmailDeadline.new(user).scan
    rescue StandardError => e
      record_failure(e, user: user, context: { watcher: "email_deadline" })
    end
end
