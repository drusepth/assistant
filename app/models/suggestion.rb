# The agent's entire output surface (D20): the agent proposes, the user
# disposes. Watchers write rows here; nothing else in the app is ever
# created, changed, or completed by the agent — accepting a suggestion is
# what materializes anything, and acceptance is always one explicit click.
# Suggestions are personal (no Visible — never shared) and Sectionable, so
# the Dashboard feed and each section's Attend zone are plain queries.
class Suggestion < ApplicationRecord
  include Sectionable

  belongs_to :user
  # The draft the agent had waiting when this suggestion arrived
  # (D-agent-prepared-work). Optional by design: a suggestion without one is
  # exactly the M3 suggestion, which is also what a failed preparation
  # degrades back to.
  belongs_to :tool_run, optional: true

  enum :kind, { nudge: "nudge", heads_up: "heads_up", insight: "insight" }, default: :nudge
  # `resolved` is retirement by the world, as distinct from `dismissed`,
  # which is retirement by the user (D-suggestion-lifecycle). Both leave the
  # fingerprint standing, so neither is ever re-proposed; the difference is
  # only what it means — and it means enough to keep apart, since "you
  # handled it" and "I didn't want this" are opposite signals to the dial
  # tuner (D-agent-earned-dials) reading the same rows.
  enum :status, { pending: "pending", accepted: "accepted", dismissed: "dismissed", snoozed: "snoozed",
                  resolved: "resolved" }, default: :pending

  validates :title, :watcher_slug, presence: true
  # The fingerprint (watcher + subject, chosen by the watcher) is what keeps
  # a dismissed nudge from reappearing on every scan.
  validates :fingerprint, presence: true, uniqueness: { scope: :user_id }

  scope :actionable, -> {
    where(status: :pending).or(where(status: :snoozed, snoozed_until: ..Date.current))
  }

  SNOOZE_FOR = 2.weeks

  def snooze!
    update!(status: :snoozed, snoozed_until: SNOOZE_FOR.from_now.to_date)
  end

  def dismiss!
    update!(status: :dismissed)
    discard_prepared_work
  end

  # The world handled it — book the checkup yourself and the nudge about
  # booking it should not be waiting for you to dismiss it by hand. Called
  # only by the scan's retire pass, never by a user action.
  def resolve!
    update!(status: :resolved)
    discard_prepared_work
  end

  # The one retirement rule that needs no watcher code: a suggestion whose
  # subject moment has passed. A nudge about last Thursday's event is the
  # app reading as broken (the D-reminders argument — a reminder more than a
  # day late is retired rather than delivered), so watchers whose subject
  # has a date stamp `expires_on` at propose time and get this for free.
  def expired?
    date = action["expires_on"]
    return false if date.blank?

    Date.iso8601(date.to_s) < Date.current
  rescue Date::Error
    false
  end

  # Materializes the action payload as ordinary primitives, tagged with the
  # suggestion's own sections, and returns what it created (nil for payloads
  # the controller handles itself, e.g. a tool redirect).
  def accept!
    created = materialize
    update!(status: :accepted)
    created
  end

  def tool_action = action["tool"]

  # ── Prepared work (D-agent-prepared-work) ────────────────────────────

  # The tool the agent may run ahead of the click, or nil. Derived, so no
  # watcher writes a line to opt in: a suggestion is preparable exactly when
  # its action already names a draft tool and prefills every input the form
  # would ask for — i.e. when there is nothing left for the user to answer.
  # Plan tools are excluded (a prepared Goal is a whole deferred graph, and
  # wants the seam proven first) and chat tools inherently so — a
  # conversation cannot be had in advance.
  def preparable_tool
    return nil unless tool_action.is_a?(Hash)

    tool = Tool.find(tool_action["slug"].to_s)
    return nil unless tool && tool.kind == :draft && tool.preparable

    given = tool_action["inputs"] || {}
    tool.inputs.select(&:required?).all? { |input| given[input.name].present? } ? tool : nil
  end

  # A draft is waiting. Guarded on the run's own status so a discarded or
  # half-written run never advertises itself as one.
  def prepared? = tool_run&.prepared?

  # An in-app destination ("look at these photos") — internal paths only,
  # so a payload can never send the user off the instance.
  def path_action
    path = action["path"]
    path if path.is_a?(String) && path.start_with?("/")
  end

  def accept_label
    # A waiting draft outranks the payload's own copy: "Review draft" is
    # what the click actually does now, and promising anything else would
    # be describing the M3 behavior this suggestion no longer has.
    return "Review draft" if prepared?
    return action["accept_label"] if action["accept_label"].present?
    return "Add task" if action["task"]
    return "Add event" if action["event"]
    return "Do it today" if action["schedule_task"]
    return "Log it" if action["spending"]
    return "Open tool" if tool_action
    return "View" if path_action

    "Accept"
  end

  def accept_notice(created)
    if (dial = action["agent_level"])
      section = Section.find_by(slug: dial["section"])
      return "Assistant set to #{dial["level"]} for #{section&.name}." if section
    end
    return "Done." if created.nil?
    return "Logged #{created.display_merchant} to your spending." if created.is_a?(SpendingTransaction)

    action["schedule_task"] ? "“#{created.title}” is now due today." : "Added “#{created.title}”."
  end

  private
    # A draft never outlives the nudge that occasioned it
    # (D-agent-prepared-work): a prepared response letter about a bill the
    # user has since paid is worse than a stale nudge, because it looks like
    # work waiting to be done. Retiring the suggestion retires the draft,
    # whether the world resolved it or the user waved it away.
    def discard_prepared_work
      tool_run.discard! if tool_run&.prepared?
    end

    # A payload may carry several keys (birthday radar lands a gift task
    # *and* the day on the calendar); each present key materializes, and the
    # first creation names the flash notice.
    def materialize
      created = []

      if (attrs = action["task"])
        task = user.tasks.create!(
          title: attrs["title"], notes: attrs["notes"],
          due_on: attrs["due_on"].presence, bucket: :today
        )
        task.sections = sections.to_a
        created << task
      end

      if (attrs = action["event"])
        event = user.events.create!(
          title: attrs["title"], starts_at: attrs["starts_at"], all_day: attrs.fetch("all_day", true)
        )
        event.sections = sections.to_a
        created << event
      end

      if (attrs = action["spending"])
        # The one path from a mirror to the ledger (docs/MONEY.md §2.1):
        # a receipt becomes a transaction only when the user says so, and
        # it lands on their Cash account like any hand-logged row.
        account = Spending::QuickLog.cash_account(user)
        occurred_on = (Date.iso8601(attrs["occurred_on"].to_s) rescue Date.current)
        created << SpendingTransaction.create!(
          user_id: user_id, spending_account_id: account.id,
          occurred_on: occurred_on, amount_cents: attrs["amount_cents"].to_i,
          descriptor: attrs["descriptor"], merchant: attrs["merchant"],
          fingerprint: "receipt-#{SecureRandom.hex(10)}", source: "email_receipt")
        Spending::Categorize.new(user: user).apply_deterministic
      end

      if (attrs = action["agent_level"])
        # The agent tuning itself (D-agent-earned-dials) — the one action
        # that changes a setting rather than creating a primitive, and it
        # still only moves on this click. Validated against the closed set
        # and the user's own row: a payload can never widen anyone's dials
        # but the owner's, or to a level that doesn't exist.
        section = Section.find_by(slug: attrs["section"])
        level = attrs["level"]
        if section && UserSection::AGENT_LEVELS.include?(level)
          user.user_sections.find_or_initialize_by(section: section).update!(agent_level: level)
        end
      end

      if (attrs = action["schedule_task"])
        # Pulls an existing task into Today instead of creating anything. The
        # date is stamped at accept time, not scan time, so a nudge accepted
        # days later still means "today". A task completed or deleted in the
        # meantime is simply nothing left to do.
        task = user.tasks.open.find_by(id: attrs["id"])
        task&.update!(due_on: Date.current, bucket: :today)
        created << task if task
      end

      created.first
    end
end
