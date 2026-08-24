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
  before_action :set_entry, only: %i[ show edit update destroy ]
  before_action :require_unlocked, only: %i[ show edit update settings ]
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

    @on_this_day = @diary.open_all(
      Current.user.diary_entries.on_day_of_year(Date.current)
        .where.not(entry_date: Date.current.beginning_of_year..Date.current.end_of_year).newest_first
    ).reject(&:lost?)
  end

  # The one dial the diary owns for itself; the emergency dial lands in W4.
  def settings
    @diary.setting_for_update.update!(prompts_enabled: params[:prompts_enabled] == "1")
    redirect_to diary_entries_path, notice: "Saved."
  end

  def show
    @opened = @diary.open(@entry)
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

  private
    def set_diary
      @diary = Diary::Session.new(Current.user, vault_key)
      @keyring = Current.user.keyring
    end

    # Owner-only for now; W4's sharing widens this to `visible_to`.
    def set_entry
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
