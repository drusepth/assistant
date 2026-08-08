# The mail browser (EMAIL_PLAN.md §7): the assistant's owner-only view of
# mirrored mailboxes — deliberately not a mail client. Unified across a
# user's email links, searchable, and the promotion surface. Strictly
# owner-scoped: there is no visible_to path to the mirror (D30), so every
# query here starts from Current.user's id.
class MailController < ApplicationController
  THREAD_LIMIT = 100

  before_action :set_accounts
  before_action :require_mailbox
  before_action :set_message, except: :index

  def index
    scope = EmailMessage.where(user_id: Current.user.id)
    if params[:account].present? && @accounts.map(&:id).include?(params[:account].to_i)
      scope = scope.where(linked_account_id: params[:account].to_i)
    end

    @query = params[:q].to_s.strip
    scope = search(scope, @query) if @query.present?

    # Triage filters (E2): labels power the chips; Everything is the default.
    @filter = params[:filter].presence_in(%w[ action time ])
    case @filter
    when "action" then scope = scope.where("json_extract(triage, '$.category') = 'action_needed'")
    when "time" then scope = scope.where("json_extract(triage, '$.category') = 'time_sensitive'")
    end

    messages = scope.newest_first.limit(THREAD_LIMIT * 6).to_a
    @threads = messages.group_by(&:thread_key).values.first(THREAD_LIMIT)
    @backfilling = EmailFolder.where(linked_account_id: @accounts.map(&:id), backfilled_at: nil).exists?
    @mirrored_count = EmailMessage.where(user_id: Current.user.id).count
  end

  def show
    @thread = @message.thread_messages.to_a
  end

  def promote
    item = case params[:kind]
    when "task" then promoter.to_task
    when "event" then promoter.to_event(params[:date])
    when "note" then promoter.to_note
    when "document" then promoter.to_document(params[:attachment])
    else return redirect_to mail_path(@message), alert: "Unknown promotion."
    end

    if item.is_a?(Document)
      redirect_to item, notice: "Attachment saved to the vault — decode or analyze it from here."
    else
      redirect_to mail_path(@message), notice: "#{item.model_name.human} created from this email."
    end
  rescue Email::Promote::Error => e
    redirect_to mail_path(@message), alert: e.message
  end

  # The user-armed boomerang (EMAIL_PLAN.md §7): zero AI, zero false
  # positives — the user declared they expect a reply.
  def remind
    date = begin
      Date.parse(params[:on].to_s)
    rescue ArgumentError
      nil
    end
    return redirect_to mail_path(@message), alert: "Pick a day to check back on." unless date
    return redirect_to mail_path(@message), alert: "Reply reminders only make sense on mail you sent." unless @message.outbound?

    @message.update!(reply_wanted_by: date)
    redirect_to mail_path(@message), notice: "You'll get a nudge if there's no reply by #{date.strftime('%b %-d')}."
  end

  def destroy
    @message.remove_from_mirror!
    redirect_to mail_index_path,
      notice: "Removed from the assistant's mirror for good — your actual mailbox is untouched."
  end

  # Lazy triage for history (EMAIL_PLAN.md §6): backfilled mail is never
  # labeled on its own, but a user opening a thread may ask.
  def triage
    ids = @message.thread_messages.where(triaged_at: nil).pluck(:id)
    if ids.any?
      Email::TriageJob.perform_later(@message.linked_account, ids)
      redirect_to mail_path(@message), notice: "Labeling this thread — refresh in a moment."
    else
      redirect_to mail_path(@message), notice: "This thread is already labeled."
    end
  end

  private
    def set_accounts
      @accounts = Current.user.linked_accounts.where(provider: "email").order(:created_at).to_a
    end

    def require_mailbox
      redirect_to settings_path, alert: "Link an email account first — the assistant can only see mail you've connected." if @accounts.empty?
    end

    def set_message
      @message = EmailMessage.where(user_id: Current.user.id).find(params[:id])
    end

    def promoter = Email::Promote.new(@message)

    def search(scope, query)
      ids = Email::Search.match_ids(query)
      return scope.where(id: ids) unless ids.nil?

      like = "%#{EmailMessage.sanitize_sql_like(query)}%"
      scope.where("subject LIKE :q OR body_text LIKE :q OR from_email LIKE :q OR from_name LIKE :q", q: like)
    end
end
