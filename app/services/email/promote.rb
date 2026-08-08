# Promotion (D30): the one door from the mirror into the primitive pool,
# always behind a human click. Content is COPIED out — the primitive
# never references the cache — and provenance lands in email_message_items
# so the message page can show what it became. D16 capture rules apply:
# minimal records, auto-sort files the sections.
class Email::Promote
  class Error < StandardError; end

  def initialize(message)
    @message = message
    @user = message.user or raise Error, "This message's owner no longer exists."
  end

  def to_task
    record(@user.tasks.create!(title: title_for("Follow up on"), notes: provenance_line).tap(&:enqueue_auto_sort!))
  end

  def to_event(date)
    date = parse_date(date) || @message.sent_at&.to_date || Date.current
    record(@user.events.create!(
      title: @message.subject.presence || "From email",
      starts_at: date.in_time_zone.change(hour: 0),
      all_day: true,
      description: provenance_line).tap(&:enqueue_auto_sort!))
  end

  def to_note
    body = [ provenance_line, @message.body_text.presence ].compact.join("\n\n")
    record(@user.notes.create!(title: @message.subject.presence, body: body).tap(&:enqueue_auto_sort!))
  end

  # The only moment attachment BYTES enter the app (EMAIL_PLAN.md §4):
  # fetched from the server on demand, landed as an ordinary Document —
  # which hands scary mail to AnalyzeDocumentJob and decode-letter (D28).
  def to_document(attachment_index)
    meta = Array(@message.attachments)[attachment_index.to_i] or
      raise Error, "That attachment isn't on this message."

    attachment = fetch_attachment(attachment_index.to_i, meta)
    document = @user.documents.create!(title: meta["filename"].presence || "Email attachment")
    document.file.attach(
      io: StringIO.new(attachment.body.decoded),
      filename: meta["filename"].presence || "attachment",
      content_type: meta["mime"].presence || "application/octet-stream")
    document.enqueue_analysis! if document.analyzable_profile
    record(document)
  end

  private
    def record(item)
      EmailMessageItem.create!(email_message: @message, item_type: item.class.name, item_id: item.id)
      item
    end

    def title_for(prefix)
      @message.subject.presence ? "#{prefix} \"#{@message.subject.first(120)}\"" : "#{prefix} an email"
    end

    def provenance_line
      who = @message.inbound? ? (@message.from_name.presence || @message.from_email) : Array(@message.to_emails).first
      date = @message.sent_at&.to_date
      "From email #{@message.inbound? ? "from" : "to"} #{who}#{" on #{date}" if date}: #{@message.snippet}".strip
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def fetch_attachment(index, meta)
      account = @message.linked_account or raise Error, "This mailbox is no longer linked."
      raise Error, "Reading mail is switched off for this link." unless account.allows?("read_inbox")

      client = Email::ImapClient.new(
        host: account.credentials["host"],
        username: account.credentials["username"],
        password: account.credentials["password"])
      begin
        raw = client.fetch_raw(@message.email_folder.name, [ @message.uid ]).first&.dig(:raw) or
          raise Error, "The server no longer has this message — it may have been moved or deleted."
        mail = Mail.read_from_string(raw)
        mail.attachments[index] or raise Error, "The attachment \"#{meta['filename']}\" wasn't found on the server copy."
      ensure
        client.disconnect
      end
    rescue Email::ImapClient::Error => e
      raise Error, e.message
    end
end
