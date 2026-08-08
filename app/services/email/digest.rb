# The daily mail digest (EMAIL_PLAN.md §7): deterministic selection, LLM
# phrasing, in-app body — the Users::WeeklyDigest recipe applied to mail,
# merged across every digest-enabled link. An empty selection stores
# nothing and sends nothing: silence is a feature.
class Email::Digest
  MAX_ITEMS = 10
  MIN_IMPORTANCE = 2

  def initialize(user)
    @user = user
  end

  def call
    items = select_items
    if items.empty?
      @user.update!(mail_digest: nil, mail_digest_generated_on: Date.current)
      return
    end

    @user.update!(
      mail_digest: { "date" => Date.current.iso8601, "phrased" => phrase(items), "items" => items },
      mail_digest_generated_on: Date.current)

    notify(items) if @user.mail_digest_notify?
  end

  private
    def accounts
      @accounts ||= @user.linked_accounts.where(provider: "email")
        .reject { |account| account.setting(:digest) == false }
    end

    # Deterministic: live arrivals since the last digest, important per
    # triage (sender rules already shaped importance), newest first.
    def select_items
      since = (@user.mail_digest_generated_on || Date.yesterday).in_time_zone(@user.household.zone)
      EmailMessage.where(linked_account_id: accounts.map(&:id), backfilled: false)
        .where("importance >= ?", MIN_IMPORTANCE)
        .where("created_at > ?", since)
        .newest_first.limit(MAX_ITEMS)
        .map do |message|
          { "id" => message.id,
            "from" => message.from_name.presence || message.from_email,
            "from_email" => message.from_email,
            "subject" => message.subject.presence || "(no subject)",
            "category" => message.triage&.dig("category"),
            "why" => message.triage&.dig("why"),
            "deadline_on" => message.triage&.dig("deadline_on") }
        end
    end

    # Two or three warm sentences over the deterministic facts; silent
    # failure — the list renders regardless. Skipped when no model or
    # every link has AI processing off.
    def phrase(items)
      profile = @user.household.model_profile
      return nil unless profile&.configured?
      return nil if accounts.all? { |account| account.setting(:ai_processing) == false }

      facts = items.map { |item| "- From #{item['from']}: #{item['subject']}#{" (deadline #{item['deadline_on']})" if item['deadline_on']}" }
      profile.client.chat([
        { role: "system", content: <<~PROMPT },
          You summarize a day's important mail for a private assistant. From the
          facts below — and ONLY the facts below, invent nothing — write two or
          three plain sentences: what came in and what deserves attention first.
          Warm, concrete, no markdown, no greetings.
        PROMPT
        { role: "user", content: facts.join("\n") }
      ]).to_s.strip.truncate(500).presence
    rescue Llm::Error => e
      AppError.record(e, source: "email_digest", user: @user)
      nil
    end

    # The D22 pointer: counts and header-derived titles only, never bodies
    # or model prose.
    def notify(items)
      titles = items.first(3).map { |item| "#{item['from']}: #{item['subject']}".truncate(80) }
      summary = "Mail digest — #{items.size} #{"message".pluralize(items.size)} worth a look: #{titles.join('; ')}"
      NotifyJob.perform_later(@user, titles, summary: summary)
    end
end
