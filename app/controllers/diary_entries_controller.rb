# The diary (D-diary-vault). Every route lives under /diary so the
# path-scoped keyring cookie covers exactly this surface.
#
# Two rules shape the whole controller. **Writing never waits on a
# password** — capture is the habit, and a diary that demands an unlock
# before you can get a thought down is a diary people stop keeping — so
# `new`/`create` work locked. **Reading always needs one**: there is no
# metadata tier here, so a locked diary can render its calendar and its
# dates and literally nothing else.
class DiaryEntriesController < ApplicationController
  # A page of entries is a page of decrypts, so the list is windowed rather
  # than capped — before this, a journal past its first couple of hundred
  # entries simply had no way to reach the older ones.
  PER_PAGE = 50
  SEARCH_LIMIT = 100

  rate_limit to: 10, within: 3.minutes, only: :unlock,
    with: -> { redirect_to diary_entries_path, alert: "Try again later." }

  before_action :set_diary
  before_action :set_readable_entry, only: %i[ show ]
  before_action :set_own_entry, only: %i[ edit update destroy share unshare history restore ]
  before_action :require_unlocked,
    only: %i[ show edit update settings export new_import create_import import_step cancel_import
              share unshare history restore ]
  before_action :require_writable_vault, only: %i[ new create ]
  after_action :never_store

  def index
    # Searching a locked diary is meaningless — there is no plaintext to
    # match — so the query is dropped rather than echoed back over a list
    # that can only show dates.
    @query = @diary.unlocked? ? params[:q].to_s.strip : ""
    @month = month_param
    @streak = Diary::Streak.new(all_entry_dates).length
    @dates_with_entries = all_entry_dates.to_set
    @today = Current.user.diary_entries.on(Date.current).first
    @entries_by_date = Current.user.diary_entries.in_month(@month).newest_first.index_by(&:entry_date)

    # Search decrypts, so it only exists unlocked — and it reaches the whole
    # journal rather than the page-sized slice the list shows.
    scope = Current.user.diary_entries.newest_first
    if @query.present?
      results = @diary.search(scope, @query, limit: SEARCH_LIMIT + 1)
      @more_results = results.size > SEARCH_LIMIT
      @opened = results.take(SEARCH_LIMIT)
    else
      # One page past the end tells the view whether there's an "older" link
      # without a second count query.
      @page = [ params[:page].to_i, 1 ].max
      window = @diary.open_all(scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1))
      @older = window.size > PER_PAGE
      @opened = window.take(PER_PAGE)
    end

    # Never interleaved with the writer's own journal — someone else's
    # entry is a different kind of thing, and it belongs in its own place.
    @shared_with_me = @diary.open_all(
      DiaryEntry.visible_to(Current.user).where.not(user_id: Current.user.id)
        .includes(:user).newest_first
    ).reject(&:lost?)

    @on_this_day = @diary.open_all(
      Current.user.diary_entries.on_day_of_year(Date.current)
        .where.not(entry_date: Date.current.beginning_of_year..Date.current.end_of_year).newest_first
    ).reject(&:lost?)
  end

  def settings
    setting = @diary.setting_for_update
    setting.update!(prompts_enabled: params[:prompts_enabled] == "1") if params.key?(:prompts_enabled)
    setting.update!(emergency_included: params[:emergency_included] == "1") if params.key?(:emergency_included)
    redirect_to diary_entries_path, notice: "Saved."
  end

  def show
    @opened = @diary.open(@entry)
    @own = @entry.user_id == Current.user.id
    return unless @own

    @shared_with = @entry.shared_with
    @eligible = Current.user.household.users.where.not(id: [ Current.user.id, *@shared_with.map(&:id) ])
      .select { |member| member.keyring.present? }
    @events = @entry.vault_events.includes(:actor, :subject_user).newest_first.limit(10)
  end

  def new
    @entry = Current.user.diary_entries.new(entry_date: entry_date_param(Date.current))
    @opened = Diary::Opened.new(@entry, {})
    @prompt = Diary::Prompts.for(@entry.entry_date) if @diary.prompts?
  end

  # Reached by the visible Save *and* by the first autosave of a new entry —
  # same sealing path either way, only the response differs.
  def create
    @entry = Current.user.diary_entries.new(entry_date: entry_date_param(Date.current))
    payload = payload_params

    if payload["body"].blank?
      return respond_to do |format|
        format.json { render json: { error: "empty" }, status: :unprocessable_entity }
        format.html do
          @entry.errors.add(:base, "Write something first.")
          @opened = Diary::Opened.new(@entry, payload)
          @prompt = Diary::Prompts.for(@entry.entry_date) if @diary.prompts?
          render :new, status: :unprocessable_entity
        end
      end
    end

    @diary.write!(@entry, payload)

    respond_to do |format|
      # The url comes back so the editor can re-point itself at the entry it
      # just created; without it the visible Save would post a second copy.
      format.json { render json: saved_payload(@entry).merge(url: diary_entry_path(@entry)) }
      format.html { redirect_to diary_entry_path(@entry), notice: "Saved to your diary." }
    end
  end

  def edit
    @opened = @diary.open(@entry)
    return unless @opened.lost?

    redirect_to diary_entry_path(@entry), alert: "This entry can't be opened."
  end

  def update
    @entry.entry_date = entry_date_param(@entry.entry_date)
    @entry.lock_version = params[:diary_entry][:lock_version] if params.dig(:diary_entry, :lock_version)
    saved = @entry.save && @diary.update!(@entry, payload_params)

    respond_to do |format|
      # Autosave: a bare fact, no page, no flash to pile up behind the
      # writer while they're still typing.
      format.json do
        if saved
          render json: saved_payload(@entry)
        else
          render json: { error: "unsaved" }, status: :unprocessable_entity
        end
      end
      format.html do
        if saved
          redirect_to diary_entry_path(@entry), notice: "Saved."
        else
          @opened = Diary::Opened.new(@entry, payload_params)
          render :edit, status: :unprocessable_entity
        end
      end
    end
  rescue ActiveRecord::StaleObjectError
    # Another tab (or another device) saved this entry since this form was
    # rendered. Refusing is the only safe answer: the two versions differ by
    # whatever the writer typed in the other window, and silently keeping
    # one would throw the other away without ever saying so.
    stale_entry_response
  end

  def destroy
    @entry.destroy!
    redirect_to diary_entries_path, notice: "Entry deleted."
  end

  # --- undo ---

  def history
    @revisions = @diary.revisions(@entry)
    @opened = @diary.open(@entry)
  end

  def restore
    revision = @entry.diary_revisions.find(params[:revision_id])

    if @diary.restore!(@entry, revision)
      redirect_to diary_entry_path(@entry),
        notice: "Restored the version from #{l(revision.created_at, format: :short)}. The version you replaced is in the history."
    else
      redirect_to history_diary_entry_path(@entry), alert: "That version couldn't be opened."
    end
  end

  # --- vault lifecycle ---

  def unlock
    unless Current.user.authenticate(params[:password].to_s)
      return redirect_to diary_entries_path, alert: "That's not your password."
    end

    if unlock_vault_for(Current.user, params[:password])
      redirect_to return_to_path(diary_entries_path), notice: "Diary unlocked."
    else
      redirect_to diary_entries_path,
        alert: "Your vault couldn't be unlocked with that password — if you recently reset it, use your recovery code from the password-reset page."
    end
  end

  def lock
    lock_vault
    redirect_to diary_entries_path, notice: "Diary locked."
  end

  # --- sharing (W4) ---

  # The one exception to private-absolutely, and it is per-entry on purpose:
  # there is no "share my diary" grant, and because entries carry no
  # taggings there is no section grant that could ever amount to one.
  def share
    grantees = Current.user.household.users.where(id: params[:grantee_id])
    result = Vault::Share.new(@entry, Current.user, vault_key).grant(grantees)

    if result.shared.positive?
      redirect_to diary_entry_path(@entry), notice: "Shared with #{result.names.to_sentence}."
    else
      redirect_to diary_entry_path(@entry), alert: result.error || "Nobody new to share with."
    end
  end

  def unshare
    grantee = Current.user.household.users.find(params[:grantee_id])

    if Vault::Share.new(@entry, Current.user, vault_key).revoke(grantee)
      redirect_to diary_entry_path(@entry),
        notice: "#{grantee.name} can't open this any more — though nothing un-reads what they already read."
    else
      redirect_to diary_entry_path(@entry), alert: "Couldn't revoke — try again."
    end
  end

  # --- doors (W3) ---

  # In-request only, like the passwords export: the archive job runs where
  # the vault key must never travel, so this button is the only thing that
  # can produce readable entries.
  def export
    unless Current.user.authenticate(params[:password].to_s)
      return redirect_to diary_entries_path, alert: "Confirm the export with your password."
    end

    archive = Diary::Export.new(@diary)
    send_data archive.zip.read, filename: archive.filename, type: "application/zip"
  end

  def new_import
    @import = Current.user.diary_imports.first
  end

  # Parses and deduplicates once, then hands off to the batch walker. A
  # decade of someone's journal is thousands of seals and thousands of
  # inserts — more than one request should hold, and a background job is
  # exactly what this container may not use.
  def create_import
    return redirect_to import_diary_entries_path, alert: "Pick a file first." if params[:file].blank?

    Current.user.diary_imports.destroy_all # one import at a time; a new file replaces an abandoned one
    @import = Diary::Import.new(@diary, params[:file], filename: params[:file].original_filename).stage!
    redirect_to import_diary_entries_path
  rescue Diary::Import::Error => error
    redirect_to import_diary_entries_path, alert: error.message
  end

  # One batch per call, driven by the page until it reports done.
  def import_step
    import = Current.user.diary_imports.first
    return render json: { done: true, percent: 100 }, status: :ok if import.nil?

    progress = Diary::ImportRun.new(@diary, import).step!
    render json: progress.to_h
  end

  def cancel_import
    Current.user.diary_imports.destroy_all
    redirect_to import_diary_entries_path, notice: "Import cancelled — nothing more will be added."
  end

  private
    def set_diary
      @diary = Diary::Session.new(Current.user, vault_key)
      @keyring = Current.user.keyring
    end

    # Reading widens to whoever holds a grant; everything that *changes* an
    # entry stays the author's alone. A shared diary entry is read-only for
    # the reader, exactly as a shared credential is.
    def set_readable_entry
      @entry = DiaryEntry.visible_to(Current.user).find(params[:id])
    end

    def set_own_entry
      @entry = Current.user.diary_entries.find(params[:id])
    end

    def require_unlocked
      return if @diary.unlocked?

      redirect_to diary_entries_path(return_to: request.path), alert: "Unlock your diary to read it."
    end

    # Two gates on writing, both about not losing words:
    #
    # A keyring must exist at all — capture while locked still needs the
    # owner's public key to wrap the item key to.
    #
    # And the recovery kit is a *gate* here, not the nag it is on the
    # passwords page (DIARY_PLAN §4.5). A vault reset without the code costs
    # you a re-entered password there; here it costs every word you ever
    # wrote, and there is no re-share to recover it from because nobody else
    # holds a key to your diary.
    def require_writable_vault
      if @keyring.nil?
        redirect_to diary_entries_path, alert: "Sign in again to set up your vault first."
      elsif !@keyring.recovery_verified?
        redirect_to diary_entries_path, alert: "Check your recovery code before you start writing."
      end
    end

    def saved_payload(entry)
      { saved_at: l(Time.current, format: :short), lock_version: entry.reload.lock_version }
    end

    STALE_MESSAGE = "This entry was saved somewhere else — reload to see that version before editing here.".freeze

    def stale_entry_response
      respond_to do |format|
        format.json { render json: { error: "stale", message: STALE_MESSAGE }, status: :conflict }
        format.html { redirect_to diary_entry_path(@entry), alert: STALE_MESSAGE }
      end
    end

    def entry_date_param(fallback)
      Date.parse(params[:entry_date].to_s)
    rescue Date::Error, TypeError
      fallback
    end

    def month_param
      Date.parse("#{params[:month]}-01")
    rescue Date::Error, TypeError
      Date.current.beginning_of_month
    end

    def all_entry_dates
      @all_entry_dates ||= Current.user.diary_entries.pluck(:entry_date).map(&:to_date)
    end

    # Everything sealed rides params[:diary], which `filter_parameters`
    # drops as a whole subtree — so no title or body reaches a log line.
    # Nothing here ever reaches a job, a prompt, or an AppError context.
    def payload_params
      params.fetch(:diary, ActionController::Parameters.new).permit(:title, :body, :mood).to_h
    end

    # No page of this diary belongs in a cache, a proxy, or Turbo's
    # back-button snapshot.
    def never_store
      response.headers["Cache-Control"] = "no-store"
    end
end
