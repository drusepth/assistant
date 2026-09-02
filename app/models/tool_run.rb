# One tool invocation and its paper trail (D19): the inputs the user gave,
# where the run stands, and the primitives it created. The show page doubles
# as the live progress surface and history — "the letter I drafted in March."
# Runs are the owner's private surface (no Visible): the primitives a run
# creates follow the normal sharing rules on their own pages.
class ToolRun < ApplicationRecord
  belongs_to :user
  # What the run is about (D30): a chat run bound to a primitive (today: a
  # Task) lives on that item's page instead of standing alone.
  belongs_to :subject, polymorphic: true, optional: true
  has_many :tool_run_items, dependent: :destroy
  has_many :tool_run_messages, dependent: :destroy
  # The suggestion this run was prepared for, if any (D-agent-prepared-work).
  # Nullify rather than destroy: a discarded draft must not take the nudge
  # that occasioned it down with it — the user may still want the plain
  # prefilled form the suggestion falls back to.
  has_one :suggestion, dependent: :nullify

  # `prepared` and `discarded` are the agent's states (D-agent-prepared-work):
  # a prepared run has made its model call and written down what it *would*
  # create, and lands nothing until the user's Save turns those intents into
  # rows. `discarded` is the answer to the other button.
  enum :status, { queued: "queued", running: "running", done: "done", failed: "failed",
                  prepared: "prepared", discarded: "discarded" }, default: :queued

  # Who asked for the run. An agent run is speculative until the user says
  # otherwise, so it is labeled wherever runs appear.
  enum :origin, { user_asked: "user", agent: "agent" }, default: :user_asked, prefix: true

  # Set for the duration of a preparation call, never persisted: it tells
  # the landing helpers in Tool::Base to write intents instead of rows. A
  # run loaded from the database is never preparing, which is what keeps an
  # ordinary run from accidentally landing nothing.
  attr_accessor :preparing

  validates :tool_slug, inclusion: { in: Tool::SLUGS }
  validate :required_inputs_present, on: :create

  def tool = Tool.find!(tool_slug)

  def items
    tool_run_items.includes(:item).map(&:item).compact
  end

  NextStep = Data.define(:tool, :inputs, :reason)

  # Follow-on tools this run proposed (D28) — sanitized at write time by
  # Tool::Base#store_next_tools, re-resolved against the registry at read
  # time so a retired slug can never break the page.
  def next_steps
    Array(output["next_tools"]).filter_map do |entry|
      next unless entry.is_a?(Hash)

      tool = Tool.find(entry["slug"])
      NextStep.new(tool: tool, inputs: entry["inputs"] || {}, reason: entry["reason"]) if tool
    end
  end

  # ── Prepared work (D-agent-prepared-work) ────────────────────────────

  # What a prepared run would create, for the review page to show before
  # the user commits to any of it — each intent previewed by its landing
  # kind (D-landing-registry). Re-read from the payload each time rather
  # than cached, since a discard can empty it.
  def landings
    Array(output["landings"]).filter_map do |landing|
      next unless landing.is_a?(Hash) && landing["title"].present?

      kind = ::Landing.find(landing["kind"]) or next
      kind.new(landing_context).preview(landing.except("kind", "sections"))
    end
  end

  # The D20 click, arriving late: the intents become ordinary primitives,
  # filed exactly where the tool filed them, recorded on the run like any
  # other run's output. Dates are resolved *now*, not at preparation time —
  # a draft prepared on Monday and saved on Thursday means Thursday, the
  # same rule the schedule_task payload already follows.
  def land!
    created = Array(output["landings"]).filter_map { |landing| land_one(landing) }
    update!(status: :done)
    created
  end

  def discard! = update!(status: :discarded)

  def finished? = done? || failed?

  # Chat runs (D29): done means *live* — the opening message is in and the
  # composer stays open; there is no finished state short of leaving.
  def chat? = tool.kind == :chat

  # A reply is pending exactly when the newest message is the user's — a
  # failed turn appends a notice, so the thinking indicator can't stick.
  def awaiting_reply?
    chat? && tool_run_messages.ordered.last&.user_role?
  end

  # A turn just failed: the newest message is the app's failure notice and
  # the user's turn beneath it sits unanswered — the state the "Try again"
  # button serves. Retrying drops the notice, so awaiting_reply? turns true
  # again and the thinking indicator comes back honestly.
  def reply_failed?
    chat? && tool_run_messages.ordered.last&.notice_role? &&
      tool_run_messages.conversational.ordered.last&.user_role?
  end

  # There's a session here worth wrapping up. One predicate so the recap
  # button and the recap action can never disagree about whether the click
  # would do anything — the button had a second home in the page header,
  # under a looser condition, and the two drifted.
  def recappable?
    chat? && tool_run_messages.conversational.exists?
  end

  # The tool's quick-reply chips, minus the ones the user has already sent:
  # a suggestion they've taken is clutter, not an offer.
  def unused_quick_replies
    tool.quick_replies - tool_run_messages.user_role.pluck(:content)
  end

  # A recap request is in flight — clicked but ChatRecapJob hasn't landed.
  # The staleness window unsticks the button if the job is lost outright.
  def recap_pending?
    recap_requested_at.present? && recap_requested_at > 5.minutes.ago
  end

  # The most recent Note an *earlier* session of this same tool filed — the
  # visible face of the memory the system prompt already carries, so the
  # user can see what the tutor is picking up from.
  def previous_recap
    return unless chat?

    earlier_runs = user.tool_runs.where(tool_slug: tool_slug).where(id: ...id).select(:id)
    ToolRunItem.where(tool_run_id: earlier_runs, item_type: "Note")
      .order(created_at: :desc, id: :desc).limit(5).filter_map(&:item).first
  end

  private
    # One staged intent becomes one row, through the landing registry
    # (D-landing-registry) — the same validation and write a document's
    # landing gets. Unknown kinds and intents that no longer validate are
    # dropped rather than raised on: the payload was written by an earlier
    # version of the app as easily as by this one, and a half-landed draft
    # is worse than a slightly short one.
    def land_one(landing)
      return unless landing.is_a?(Hash) && landing["title"].present?

      kind = ::Landing.find(landing["kind"]) or return
      instance = kind.new(landing_context)
      attributes = instance.validate(landing.except("kind", "sections")) or return

      item = instance.land!(attributes, sections: Section.where(id: landing["sections"]))
      tool_run_items.create!(item: item)
      item
    end

    def landing_context = @landing_context ||= ::Landing::Context.new(user: user)

    def required_inputs_present
      return unless (tool = Tool.find(tool_slug))

      tool.inputs.select(&:required?).each do |input|
        errors.add(:base, "“#{input.label}” needs an answer.") if inputs[input.name].blank?
      end
    end
end
