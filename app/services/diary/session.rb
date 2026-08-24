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

    # `repair: false` for reads that aren't the writer's own visit — an
    # emergency contact opening a diary shouldn't quietly rewrite the wraps
    # on someone else's entries.
    def initialize(user, vault_key, repair: true)
      @user = user
      @vault_key = vault_key.presence
      @repair = repair
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

      # Only the author's own entries hang off the diary key; a shared entry
      # opens through its key row, and asking for the key here would create
      # a diary for a reader who may not keep one.
      own = entry.user_id == user.id
      item_key = entry.unwrap_item_key(user, vault_key, diary_key: own ? diary_key : nil) or return nil
      payload = entry.read_secrets_with_item_key(item_key)
      repair(entry, item_key)
      payload
    end

    def open(entry) = Opened.new(entry, read(entry))

    def open_all(entries) = entries.map { |entry| open(entry) }

    # Search happens in Ruby over decrypted payloads, because there is
    # nothing else to search: no plaintext title, no index, no metadata
    # tier. That is affordable only because of the diary key — every entry
    # opens with one GCM unwrap, so scanning a whole journal is milliseconds
    # rather than a 3072-bit unwrap per row.
    def search(entries, query)
      needle = query.to_s.downcase
      return [] if needle.blank?

      open_all(entries).select do |opened|
        next false if opened.lost?

        [ opened.title, opened.body, opened.mood ].compact.any? { |field| field.downcase.include?(needle) }
      end
    end

    def prompts? = setting.nil? || setting.prompts_enabled?

    def emergency_included? = setting&.emergency_included? || false

    # Writing a dial goes through the unlocked path so the row is created
    # with a real diary key. Creating it any other way would leave a
    # settings row whose content key cannot be unwrapped — indistinguishable
    # from one a password reset broke, and it would falsely tell the writer
    # their entries were lost.
    def setting_for_update
      return nil unless unlocked?

      load_setting.first
    end

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
        return unless @repair && entry.user_id == user.id && entry.wrapped_while_locked?

        entry.rewrap_to_diary_key!(item_key, diary_key)
      rescue StandardError => error
        AppError.record(error, source: "Diary::Session#repair", user: user)
      end
  end
end
