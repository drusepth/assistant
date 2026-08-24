class ToolRunsController < ApplicationController
  before_action :set_tool, only: %i[ new create ]
  before_action :load_input_choices, only: %i[ new create ]

  def new
    @tool_run = Current.user.tool_runs.new(tool_slug: @tool.slug, inputs: prefilled_input_params)
    # Continuing beats starting over, so a chat tool offers its own recent
    # sessions above the blank form (D-chat-index). Subject-bound runs are
    # left out: those live on their item's page, not here.
    if @tool.kind == :chat
      @recent_chats = Current.user.tool_runs.where(tool_slug: @tool.slug, subject: nil)
        .order(created_at: :desc).limit(3)
    end
  end

  def create
    @tool_run = Current.user.tool_runs.new(tool_slug: @tool.slug, inputs: input_params)
    if @tool_run.save
      ToolRunJob.perform_later(@tool_run)
      redirect_to @tool_run
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @tool_run = Current.user.tool_runs.find(params[:id])
  end

  # Runs are deletable — for chats that's the trust feature (D33: a
  # check-in transcript is yours to destroy), for anything else it's tidy
  # history. Created primitives (notes, tasks, events) are their own
  # records and stay.
  def destroy
    run = Current.user.tool_runs.find(params[:id])
    section = run.tool.section_slugs.first
    notice = run.chat? ? "Conversation deleted." : "Run deleted."
    run.destroy!
    redirect_to section ? section_path(section) : root_path, notice: notice
  end

  # "Save a recap" on a chat run (D29) — the explicit click that turns a
  # session into an owned Note (D20: nothing lands without the user asking).
  # recap_requested_at is the in-flight marker: it drives the button's
  # "Saving recap…" state and keeps a double-click from filing two notes.
  def recap
    run = Current.user.tool_runs.find(params[:id])
    if run.recappable? && !run.recap_pending?
      run.update_column(:recap_requested_at, Time.current)
      ChatRecapJob.perform_later(run)
    end
    # Back to whichever chat surface the click came from — the run page or a
    # task page hosting the conversation (D30).
    redirect_back fallback_location: run
  end

  # Ask-your-email answers render on the run page without landing anything;
  # this is the explicit door into the primitive pool (D-mirror-layer) — one click,
  # one Note, auto-filed per D16.
  def save_answer
    run = Current.user.tool_runs.find(params[:id])
    answer = run.output["answer"]
    if answer.present? && run.items.grep(Note).empty?
      body = [ answer["body"],
               Array(answer["citations"]).map { |citation| "— #{citation["from"]}#{", #{citation["date"]}" if citation["date"].present?}" }.join("\n").presence
             ].compact.join("\n\nSources:\n")
      note = Current.user.notes.create!(title: "From your mail: #{answer["question"].to_s.first(80)}", body: body)
      note.enqueue_auto_sort!
      run.tool_run_items.create!(item: note)
    end
    redirect_to run
  end

  # "Try again" after a failed turn: drop the failure notice and re-enqueue
  # the reply — the user's message is answered without retyping it.
  def retry_reply
    run = Current.user.tool_runs.find(params[:id])
    if run.reply_failed?
      run.tool_run_messages.ordered.last.destroy!
      ChatTurnJob.perform_later(run)
    end
    redirect_back fallback_location: run
  end

  private
    def set_tool
      @tool = Tool.find!(params[:tool_slug])
    end

    def load_input_choices
      @document_choices = Document.visible_to(Current.user).order(created_at: :desc) if @tool.inputs.any?(&:document?)
      # Circle first (D30) — the people you're tending are almost always the
      # ones a People tool is about.
      @person_choices = Person.visible_to(Current.user).order(keep_in_touch: :desc, name: :asc) if @tool.inputs.any?(&:person?)
      # Hobby lenses (D25); with none yet the form falls back to free text,
      # so the Hobbies tools work before any lens exists.
      @hobby_choices = (Section.find_by(slug: "hobbies")&.children || Section.none) if @tool.inputs.any?(&:hobby?)
      # Envelopes are personal, not shared (D-budget-envelopes): own only,
      # no visible_to path exists.
      @budget_category_choices = Current.user.budget_categories.active.ordered if @tool.inputs.any?(&:budget_category?)
      @ledger_month_choices = Tool::SpendingReview.month_options(Current.user) if @tool.inputs.any?(&:ledger_month?)
      # Mirrored mail is strictly the owner's (D-mirror-layer) — no visible_to path.
      if @tool.inputs.any?(&:email_message?)
        @email_choices = EmailMessage.where(user_id: Current.user.id).newest_first.limit(50)
      end
    end

    # `new` accepts the same params so "Run again" and next-step links can
    # prefill from earlier inputs. Checkbox inputs arrive as arrays.
    def input_params
      permitted = @tool.inputs.map { |input| input.checkboxes? ? { input.name => [] } : input.name }
      params.fetch(:inputs, {}).permit(*permitted).to_h
    end

    # Blank form fields seeded from the user's profile (D-work-profile) —
    # only on `new`, so an explicitly cleared field on submit stays cleared.
    def prefilled_input_params
      @tool.inputs.each_with_object(input_params) do |input, filled|
        next if input.prefill.nil? || filled[input.name].present?

        value = Current.user.public_send(input.prefill)
        filled[input.name] = value if value.present?
      end
    end
end
