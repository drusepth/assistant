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
  rate_limit to: 10, within: 3.minutes, only: :unlock,
    with: -> { redirect_to diary_entries_path, alert: "Try again later." }

  before_action :set_diary
  before_action :set_readable_entry, only: %i[ show ]
  before_action :set_own_entry, only: %i[ edit update destroy share unshare ]
  before_action :require_unlocked,
    only: %i[ show edit update settings export new_import create_import share unshare ]
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
    @opened = if @query.present?
      @diary.search(scope, @query)
    else
      @diary.open_all(scope.limit(200))
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

  def create
    @entry = Current.user.diary_entries.new(entry_date: entry_date_param(Date.current))
    payload = payload_params

    if payload["body"].blank?
      @entry.errors.add(:base, "Write something first.")
      @opened = Diary::Opened.new(@entry, payload)
      @prompt = Diary::Prompts.for(@entry.entry_date) if @diary.prompts?
      return render :new, status: :unprocessable_entity
    end

    @diary.write!(@entry, payload)
    redirect_to diary_entry_path(@entry), notice: "Saved to your diary."
  end

  def edit
    @opened = @diary.open(@entry)
    return unless @opened.lost?

    redirect_to diary_entry_path(@entry), alert: "This entry can't be opened."
  end

  def update
    @entry.entry_date = entry_date_param(@entry.entry_date)
    saved = @entry.save && @diary.update!(@entry, payload_params)

    respond_to do |format|
      # Autosave: a bare fact, no page, no flash to pile up behind the
      # writer while they're still typing.
      format.json do
        if saved
          render json: { saved_at: l(Time.current, format: :short) }
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
  end

  def destroy
    @entry.destroy!
    redirect_to diary_entries_path, notice: "Entry deleted."
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
  end

  def create_import
    return redirect_to import_diary_entries_path, alert: "Pick a file first." if params[:file].blank?

    result = Diary::Import.new(@diary, params[:file], filename: params[:file].original_filename).call
    redirect_to diary_entries_path,
      notice: "#{result.imported} imported, #{result.skipped} already here."
  rescue Diary::Import::Error => error
    redirect_to import_diary_entries_path, alert: error.message
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
      elsif @keyring.recovery_pending?
        redirect_to diary_entries_path, alert: "Save your recovery kit before you start writing."
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
