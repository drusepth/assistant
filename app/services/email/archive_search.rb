# The live-archive fallback (EMAIL_PLAN.md §7): when the mirror's window
# can't answer — the question predates it, or nothing local matches — the
# same search runs against the server over the `read_archive` scope.
# Results are fetched TRANSIENTLY: parsed, handed to the caller, never
# mirrored; tombstoned messages stay invisible even here.
class Email::ArchiveSearch
  Hit = Struct.new(:from, :subject, :date, :body, :account_label, keyword_init: true)

  MAX_HITS = 8
  BODY_CHARS = 1_200

  def initialize(account, client: nil)
    @account = account
    @client = client
  end

  def call(terms, since: nil, before: nil)
    return [] unless @account.allows?("read_archive")
    return [] if @account.paused? || terms.blank?

    folders = EmailFolder.where(linked_account_id: @account.id).pluck(:name)
    return [] if folders.empty?

    uids_by_folder = folders.index_with do |folder|
      client.search(folder, terms, since: since, before: before).last(MAX_HITS)
    end

    hits = uids_by_folder.flat_map do |folder, uids|
      client.fetch_raw(folder, uids).filter_map { |fetched| to_hit(fetched[:raw]) }
    end
    hits.sort_by { |hit| hit.date || Time.at(0) }.last(MAX_HITS)
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
          password: @account.credentials["password"])
      end
    end

    def to_hit(raw)
      mail = Mail.read_from_string(raw.to_s)
      return nil if mail.message_id.present? && EmailTombstone.covers?(@account.id, mail.message_id)

      body = mail.multipart? ? mail.text_part&.decoded : mail.body&.decoded
      Hit.new(
        from: Array(mail.from).first, subject: mail.subject.to_s,
        date: (mail.date&.to_time rescue nil),
        body: body.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: " ").first(BODY_CHARS),
        account_label: @account.label)
    rescue StandardError
      nil
    end
end
