module Diary
  # One request's view of a user's diary (D-diary-vault): holds the diary
  # key so a screenful of entries costs one GCM unwrap each, and owns the
  # two rules that would otherwise be scattered across controllers —
  # capture works while locked, and reading is what repairs a locked write.
  #
  # Constructed per request from the path-scoped cookie. Nothing here is
  # ever handed to a background job: key material stays in the request that
  # holds the password-derived key, which is what keeps the diary out of the
  # queue tables and, structurally, out of every model surface.
  # One entry as a view can use it: the record plus whatever the vault would
  # give up. A locked session or a diary key lost to a password reset yields
  # `payload = nil`, and every reader below degrades to the date — which is
  # all a locked diary is allowed to render.
  Opened = Struct.new(:entry, :payload) do
    def lost? = payload.nil?
    def title = payload&.dig("title").presence
    def body = payload&.dig("body").to_s
    def mood = payload&.dig("mood").presence

    # Untitled entries are the common case — people just write — so the
    # list falls back to the opening words rather than showing "Untitled"
    # down the whole page.
    def display_title
      title || body.split("\n").first&.truncate(60).presence || "Untitled"
    end

    def preview(limit = 160)
      rest = title ? body : body.split("\n").drop(1).join(" ")
      rest.squish.truncate(limit)
    end
  end

  class Session
    attr_reader :user, :vault_key

    def initialize(user, vault_key)
      @user = user
      @vault_key = vault_key.presence
    end

    def unlocked? = vault_key.present?

    # nil while locked. Creates the diary key on first use, and re-mints it
    # when the vault key that wrapped it is gone (DiarySetting.unlock_for).
    def diary_key
      return nil unless unlocked?

      load_setting unless defined?(@diary_key)
      @diary_key
    end

    # The stored settings row, without needing an unlocked vault — the
    # emergency dial and the loss stamp are readable either way.
    def setting
      return @setting if defined?(@setting) && @setting

      unlocked? ? load_setting.first : DiarySetting.find_by(user: user)
    end

    def lost_entries? = setting&.lost_entries?

    # The decrypted payload, or nil when this entry can't be opened (locked,
    # or sealed under a diary key a password reset destroyed).
    def read(entry)
      return nil unless unlocked?

      item_key = entry.unwrap_item_key(user, vault_key, diary_key: diary_key) or return nil
      payload = entry.read_secrets_with_item_key(item_key)
      repair(entry, item_key)
      payload
    end

    def open(entry) = Opened.new(entry, read(entry))

    def open_all(entries) = entries.map { |entry| open(entry) }

    # Capture never waits on a password: with no diary key the entry seals
    # its item key to the owner's public key instead (DiaryEntry::SCHEME_RSA)
    # and the next unlocked read moves it onto the cheap wrap.
    def write!(entry, payload)
      entry.seal!(payload, diary_key: diary_key)
      entry
    end

    # Editing needs the vault: the existing payload has to be opened before
    # the merged one can be resealed under the same item key, so grantee
    # wraps stay valid.
    def update!(entry, payload)
      item_key = entry.unwrap_item_key(user, vault_key, diary_key: diary_key) or return false

      existing = entry.read_secrets_with_item_key(item_key) || {}
      entry.update_secrets!(existing.merge(payload), item_key)
      repair(entry, item_key)
      true
    end

    private
      def load_setting
        setting, key = DiarySetting.unlock_for(user, vault_key)
        @setting = setting
        @diary_key = key
        [ setting, key ]
      end

      # A performance repair, never a correctness one — an entry that fails
      # to re-wrap must still be readable, so this swallows rather than
      # raises (the D23 posture).
      def repair(entry, item_key)
        return unless entry.user_id == user.id && entry.wrapped_while_locked?

        entry.rewrap_to_diary_key!(item_key, diary_key)
      rescue StandardError => error
        AppError.record(error, source: "Diary::Session#repair", user: user)
      end
  end
end
