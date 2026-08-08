require "net/imap"

# Minimal IMAP client for the email mirror (EMAIL_PLAN.md §5) — the
# Dav::Client of mailboxes: plain net-imap, no vendor gem, a narrow
# interface the sync engine (and its test fake) share. Read-only against
# the server: nothing here ever sets a flag or writes a message.
class Email::ImapClient
  class Error < StandardError; end

  Folder = Struct.new(:name, :attrs, keyword_init: true)

  OPEN_TIMEOUT = 15
  FETCH_BATCH = 100

  def initialize(host:, username:, password:, port: 993)
    @host = host.to_s.strip
    @username = username
    @password = password
    @port = port
  end

  def folders
    wrap("listing folders") do
      (imap.list("", "*") || []).map { |item| Folder.new(name: item.name, attrs: item.attr || []) }
    end
  end

  # => { uidvalidity: Integer, uidnext: Integer }
  def status(folder)
    wrap("checking #{folder}") do
      raw = imap.status(folder, %w[ UIDVALIDITY UIDNEXT ])
      { uidvalidity: raw["UIDVALIDITY"], uidnext: raw["UIDNEXT"] }
    end
  end

  def uids_since(folder, date)
    wrap("searching #{folder}") do
      examine(folder)
      imap.uid_search([ "SINCE", date.strftime("%d-%b-%Y") ]).sort
    end
  end

  def uids_above(folder, uid)
    wrap("searching #{folder}") do
      examine(folder)
      imap.uid_search([ "UID", "#{uid + 1}:*" ]).select { |found| found > uid }.sort
    end
  end

  # => [{ uid:, raw: }] — full RFC822 source, peeked so the server's
  # unread flags stay untouched.
  def fetch_raw(folder, uids)
    return [] if uids.empty?
    wrap("fetching from #{folder}") do
      examine(folder)
      uids.each_slice(FETCH_BATCH).flat_map do |slice|
        (imap.uid_fetch(slice, "BODY.PEEK[]") || []).map do |data|
          { uid: data.attr["UID"], raw: data.attr["BODY[]"] }
        end
      end
    end
  end

  # Server-side text search (the read_archive fallback, EMAIL_PLAN.md §7):
  # every term must match (IMAP TEXT keys AND together), optional date
  # bounds. Returns UIDs, newest last.
  def search(folder, terms, since: nil, before: nil)
    wrap("searching #{folder}") do
      examine(folder)
      keys = Array(terms).flat_map { |term| [ "TEXT", term.to_s ] }
      keys += [ "SINCE", since.strftime("%d-%b-%Y") ] if since
      keys += [ "BEFORE", before.strftime("%d-%b-%Y") ] if before
      keys = [ "ALL" ] if keys.empty?
      imap.uid_search(keys).sort
    end
  end

  # => { uid => [:Seen, :Answered, ...] }
  def flags(folder, uids)
    return {} if uids.empty?
    wrap("refreshing flags in #{folder}") do
      examine(folder)
      (imap.uid_fetch(uids, "FLAGS") || []).to_h { |data| [ data.attr["UID"], data.attr["FLAGS"] || [] ] }
    end
  end

  def disconnect
    @imap&.logout
  rescue StandardError
    nil
  ensure
    begin
      @imap&.disconnect
    rescue StandardError
      nil
    end
    @imap = nil
  end

  private
    def imap
      @imap ||= begin
        raise Error, "The IMAP server address is blank." if @host.blank?
        client = Net::IMAP.new(@host, port: @port, ssl: true, open_timeout: OPEN_TIMEOUT)
        client.login(@username.to_s, @password.to_s)
        client
      rescue Net::IMAP::NoResponseError
        raise Error, "The mail server rejected the login — check the address and app password."
      rescue OpenSSL::SSL::SSLError
        raise Error, "Couldn't establish a secure connection to #{@host}."
      rescue SocketError, SystemCallError, Timeout::Error, IOError => e
        raise Error, "Couldn't reach #{@host}: #{e.message}"
      end
    end

    def examine(folder)
      return if @examined == folder
      imap.examine(folder)
      @examined = folder
    end

    def wrap(doing)
      yield
    rescue Error
      raise
    rescue Net::IMAP::Error, SocketError, SystemCallError, Timeout::Error, IOError, EOFError => e
      raise Error, "Mail sync failed while #{doing}: #{e.message}"
    end
end
