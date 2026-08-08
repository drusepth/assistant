# The mailbox mirror sync (EMAIL_PLAN.md §5): Inbox + Sent, incremental
# by UID cursor, deduped by message_id, tombstone-respecting. Two phases
# with different meanings:
#
# - Backfill (folder.backfilled_at nil): loads the retention window in
#   bounded batches — history is browse/search/promote-only, flagged
#   `backfilled`, never triaged, structurally unable to alert.
# - Live (every run after): new UIDs only, plus a flag refresh on recent
#   messages so seen/answered stay truthful. Only live arrivals enter the
#   triage/alert pipeline (E2+).
#
# Sync is model-free and read-only against the server. Scope-gated inside
# the service (D26): no "read_inbox", no sync.
class Email::ImapSync
  Error = Email::ImapClient::Error

  Result = Struct.new(:error, :new_live_ids, :more, keyword_init: true) do
    def more? = more.present?
  end

  WINDOW_DAYS_DEFAULT = 90
  BACKFILL_BATCH = 500
  FLAG_REFRESH_DAYS = 14
  SENT_NAMES = [ "sent", "sent messages", "sent items", "[gmail]/sent mail" ].freeze

  def initialize(account, client: nil)
    @account = account
    @user_id = account.user_id
    @client = client
    @learned_addresses = []
    @new_live_ids = []
    @more = false
  end

  def call
    unless @account.allows?("read_inbox")
      raise Error, "Reading mail is switched off for this link — re-enable it in Settings to sync."
    end

    tracked_folders.each { |folder| sync_folder(folder) }
    learn_own_addresses

    Result.new(error: nil, new_live_ids: @new_live_ids, more: @more)
  ensure
    client.disconnect if @client_started
  end

  private
    def client
      @client ||= begin
        @client_started = true
        Email::ImapClient.new(
          host: @account.credentials["host"],
          username: @account.credentials["username"],
          password: @account.credentials["password"]
        )
      end
    end

    # Inbox + Sent, discovered via SPECIAL-USE attributes with common-name
    # fallbacks; rows are created once and reused as cursors.
    def tracked_folders
      listed = client.folders
      inbox = listed.find { |folder| folder.name.casecmp("INBOX").zero? } || listed.first
      sent = listed.find { |folder| folder.attrs.include?(:Sent) } ||
             listed.find { |folder| SENT_NAMES.include?(folder.name.downcase) }

      # Sent first: aliases learned there decide direction for inbox
      # copies ingested in the same run.
      [ [ sent, "sent" ], [ inbox, "inbox" ] ].filter_map do |folder, role|
        next unless folder
        record = EmailFolder.find_or_create_by!(linked_account_id: @account.id, name: folder.name) do |row|
          row.user_id = @user_id
          row.role = role
        end
        record.update!(role: role) if record.role != role
        record
      end
    end

    def sync_folder(folder)
      remote = client.status(folder.name)

      # UIDVALIDITY changed: every cursor is meaningless. Start the window
      # over; message_id dedupe makes the re-mirror duplicate-free.
      if folder.uidvalidity && remote[:uidvalidity] && folder.uidvalidity != remote[:uidvalidity]
        folder.update!(uidvalidity: remote[:uidvalidity], last_seen_uid: 0, backfilled_at: nil)
      elsif folder.uidvalidity.nil?
        folder.update!(uidvalidity: remote[:uidvalidity])
      end

      folder.backfilled? ? sync_live(folder) : sync_backfill(folder)
    end

    # One bounded batch per run, oldest first, cursor advancing as it
    # goes — a huge mailbox backfills across several queued runs while the
    # UI shows "1,200 messages so far" straight from the mirror's counts.
    def sync_backfill(folder)
      pending = client.uids_since(folder.name, window_start).select { |uid| uid > folder.last_seen_uid }
      batch = pending.first(BACKFILL_BATCH)

      ingest(folder, batch, backfilled: true)
      folder.update!(last_seen_uid: batch.max) if batch.any?

      if pending.size > batch.size
        @more = true
      else
        folder.update!(backfilled_at: Time.current)
      end
    end

    def sync_live(folder)
      fresh = client.uids_above(folder.name, folder.last_seen_uid)
      created = ingest(folder, fresh, backfilled: false)
      folder.update!(last_seen_uid: fresh.max) if fresh.any?
      @new_live_ids.concat(created)

      refresh_flags(folder)
    end

    # => ids of created messages
    def ingest(folder, uids, backfilled:)
      return [] if uids.empty?

      client.fetch_raw(folder.name, uids).filter_map do |fetched|
        store(folder, fetched[:uid], fetched[:raw], backfilled: backfilled)
      end
    end

    def store(folder, uid, raw, backfilled:)
      mail = parse(raw) or return nil
      message_id = normalized_message_id(mail, raw)

      return nil if EmailTombstone.covers?(@account.id, message_id)
      return nil if EmailMessage.exists?(linked_account_id: @account.id, message_id: message_id)

      from_email = address_list(mail.from).first
      to_emails = address_list(mail.to)
      direction = direction_for(folder, from_email)
      @learned_addresses << from_email if folder.role == "sent" && from_email.present?
      body = body_text(mail)

      message = EmailMessage.create!(
        user_id: @user_id,
        linked_account_id: @account.id,
        email_folder: folder,
        uid: uid,
        message_id: message_id,
        thread_key: thread_key(mail, message_id, from_email, to_emails),
        direction: direction,
        from_email: from_email,
        from_name: display_name(mail),
        to_emails: to_emails,
        cc_emails: address_list(mail.cc),
        subject: utf8(mail.subject.to_s).presence,
        sent_at: sent_at(mail),
        person_id: match_person(direction, from_email, to_emails),
        snippet: body.squish.first(EmailMessage::SNIPPET_LENGTH).presence,
        body_text: body.first(EmailMessage::BODY_LIMIT).presence,
        attachments: attachment_metadata(mail),
        bulk: bulk?(mail, from_email),
        seen: false,
        answered: false,
        backfilled: backfilled
      )
      advance_contact_recency(message)
      message.id
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # The Q8 revisit (EMAIL_PLAN.md §7): outbound mail is OBSERVED contact,
    # not inference — with the per-link toggle on (default off), sending
    # someone mail advances their last_contacted_on, forward-only, matched
    # people only. The manual "Log contact" button remains for everyone else.
    def advance_contact_recency(message)
      return unless @account.setting(:contact_recency) == true
      return unless message.outbound? && message.person_id.present? && message.sent_at.present?

      date = message.sent_at.to_date
      return if date > Date.current

      Person.where(id: message.person_id, user_id: @user_id)
        .where("last_contacted_on IS NULL OR last_contacted_on < ?", date)
        .update_all(last_contacted_on: date)
    end

    def parse(raw)
      Mail.read_from_string(raw.to_s)
    rescue StandardError
      nil # one unparseable message must not kill the sync
    end

    def normalized_message_id(mail, raw)
      mail.message_id.presence || "missing:#{Digest::SHA256.hexdigest(raw.to_s)}"
    rescue StandardError
      "missing:#{Digest::SHA256.hexdigest(raw.to_s)}"
    end

    def address_list(addresses)
      Array(addresses).filter_map { |address| utf8(address.to_s).downcase.presence }
    end

    def display_name(mail)
      utf8(mail[:from]&.display_names&.first.to_s).presence
    rescue StandardError
      nil
    end

    def sent_at(mail)
      mail.date&.to_time
    rescue StandardError
      nil
    end

    # Outbound iff From is one of this mailbox's own addresses — the
    # user-editable, sent-folder-learned list, seeded with the login
    # (EMAIL_PLAN.md §3: aliases make this load-bearing).
    def direction_for(folder, from_email)
      known = own_addresses + @learned_addresses.compact.map(&:downcase)
      return "outbound" if from_email.present? && known.include?(from_email)
      folder.role == "sent" ? "outbound" : "inbound"
    end

    def own_addresses
      @own_addresses ||= (Array(@account.setting(:own_addresses)) +
        [ @account.credentials["username"].to_s.downcase ]).map(&:downcase).uniq.reject(&:blank?)
    end

    def learn_own_addresses
      learned = (own_addresses + @learned_addresses.compact.map(&:downcase)).uniq
      return if learned.sort == Array(@account.setting(:own_addresses)).map(&:downcase).sort

      @account.update!(settings: @account.settings.merge("own_addresses" => learned))
    end

    # Root of the References chain; the subject+participants fallback
    # applies ONLY when threading headers are entirely absent on a reply —
    # "Re: Invoice" from unrelated senders must never merge.
    def thread_key(mail, message_id, from_email, to_emails)
      references = Array(mail.references).map(&:to_s)
      return references.first if references.first.present?

      in_reply_to = Array(mail.in_reply_to).map(&:to_s)
      return in_reply_to.first if in_reply_to.first.present?

      subject = utf8(mail.subject.to_s)
      if subject.match?(/\A\s*(re|fwd?):/i)
        participants = ([ from_email ] + to_emails).compact.sort.join(",")
        base = subject.sub(/\A\s*((re|fwd?):\s*)+/i, "").squish.downcase
        return "subj:#{Digest::SHA256.hexdigest("#{base}|#{participants}")}"
      end

      message_id
    end

    # Matched to the user's own People by exact address; the sender for
    # inbound, the first recipient for outbound. Soft id (D32).
    def match_person(direction, from_email, to_emails)
      counterparty = direction == "inbound" ? from_email : to_emails.first
      return nil if counterparty.blank?
      person_ids_by_email[counterparty]
    end

    def person_ids_by_email
      @person_ids_by_email ||= Person.where(user_id: @user_id).where.not(email: [ nil, "" ])
        .pluck(:email, :id).to_h { |email, id| [ email.downcase, id ] }
    end

    def body_text(mail)
      part = mail.multipart? ? (mail.text_part || mail.html_part) : mail
      return "" unless part
      decoded = utf8(part.decoded.to_s)
      part.mime_type == "text/html" ? strip_html(decoded) : decoded
    rescue StandardError
      ""
    end

    def strip_html(html)
      visible = html.gsub(%r{<(script|style)[^>]*>.*?</\1>}mi, " ")
      text = ActionView::Base.full_sanitizer.sanitize(visible).to_s
      CGI.unescapeHTML(text).gsub(/[ \t]+/, " ")
    rescue StandardError
      html.gsub(/<[^>]+>/, " ").squeeze(" ")
    end

    def attachment_metadata(mail)
      mail.attachments.map do |attachment|
        { "filename" => utf8(attachment.filename.to_s), "mime" => attachment.mime_type,
          "size" => attachment.body.to_s.bytesize }
      end
    rescue StandardError
      []
    end

    # Computed at ingest, spent nowhere (EMAIL_PLAN.md §6): bulk mail is
    # pre-labeled noise by code and feeds the boomerang exclusions.
    def bulk?(mail, from_email)
      return true if mail["List-Unsubscribe"].present? || mail["List-Id"].present?
      return true if mail["Precedence"].to_s.match?(/bulk|list|junk/i)
      return true if mail["Auto-Submitted"].present? && mail["Auto-Submitted"].to_s !~ /\Ano\z/i
      from_email.to_s.match?(/\A(no-?reply|do-?not-?reply|notifications?|mailer-daemon)@/i)
    rescue StandardError
      false
    end

    def refresh_flags(folder)
      recent = EmailMessage.where(email_folder_id: folder.id)
        .where("sent_at > ?", FLAG_REFRESH_DAYS.days.ago)
        .pluck(:id, :uid, :seen, :answered)
      return if recent.empty?

      remote = client.flags(folder.name, recent.map { |_, uid, _, _| uid })
      recent.each do |id, uid, seen, answered|
        flags = remote[uid] or next
        now_seen = flags.include?(:Seen)
        now_answered = flags.include?(:Answered)
        next if now_seen == seen && now_answered == answered
        EmailMessage.where(id: id).update_all(seen: now_seen, answered: now_answered)
      end
    end

    def window_start
      days = @account.setting(:mirror_window_days).to_i
      days = WINDOW_DAYS_DEFAULT if days <= 0 && @account.setting(:mirror_window_days) != 0
      days <= 0 ? Date.new(1990, 1, 1) : days.days.ago.to_date
    end

    def utf8(text)
      text.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ")
    rescue StandardError
      text.to_s.force_encoding("UTF-8").scrub(" ")
    end
end
