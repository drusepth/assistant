# In-memory stand-in for Email::ImapClient (EMAIL_PLAN.md §10 testing
# conventions): the sync engine's tests run against fixture RFC822
# strings, no sockets. Mutate @mailbox between calls to simulate arrivals.
class FakeImapClient
  Folder = Email::ImapClient::Folder

  # mailbox: { "INBOX" => { attrs: [], uidvalidity: 1, messages: { uid => raw } }, ... }
  attr_accessor :mailbox, :flag_map

  def initialize(mailbox, flag_map: {})
    @mailbox = mailbox
    @flag_map = flag_map
    @disconnected = false
  end

  def folders
    @mailbox.map { |name, folder| Folder.new(name: name, attrs: folder.fetch(:attrs, [])) }
  end

  def status(name)
    folder = @mailbox.fetch(name)
    uids = folder.fetch(:messages, {}).keys
    { uidvalidity: folder.fetch(:uidvalidity, 1), uidnext: (uids.max || 0) + 1 }
  end

  def uids_since(name, _date)
    @mailbox.fetch(name).fetch(:messages, {}).keys.sort
  end

  def uids_above(name, uid)
    uids_since(name, nil).select { |found| found > uid }
  end

  def fetch_raw(name, uids)
    messages = @mailbox.fetch(name).fetch(:messages, {})
    uids.filter_map { |uid| { uid: uid, raw: messages[uid] } if messages[uid] }
  end

  def flags(name, uids)
    uids.index_with { |uid| @flag_map.dig(name, uid) || [] }
  end

  def disconnect = @disconnected = true
  def disconnected? = @disconnected
end

module EmailFixtureHelper
  # A minimal, valid RFC822 message. Every field overridable.
  def rfc822(from:, to:, subject:, body:, message_id:, date: Time.current,
             cc: nil, references: nil, in_reply_to: nil, list_unsubscribe: nil, html: false)
    mail = Mail.new
    mail.from = from
    mail.to = to
    mail.cc = cc if cc
    mail.subject = subject
    mail.message_id = message_id
    mail.date = date
    mail.references = references if references
    mail.in_reply_to = in_reply_to if in_reply_to
    mail.header["List-Unsubscribe"] = list_unsubscribe if list_unsubscribe
    if html
      mail.content_type = "text/html; charset=UTF-8"
      mail.body = body
    else
      mail.body = body
    end
    mail.to_s
  end
end
