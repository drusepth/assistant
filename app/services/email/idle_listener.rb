# Real-time mail (EMAIL_PLAN.md §5, E6): a small supervised process —
# run as `bin/email-listener`, its own entry in the container's process
# tree next to the web server and worker — holding one IMAP IDLE
# connection per alert-enabled link and enqueuing the ordinary sync job
# the moment the server signals. IDLE is in the IMAP standard, so this
# works against every server with no provider console (the
# self-host-friendly, landlord-free version of "instant").
#
# Deliberately optional: polling remains the universal fallback, so a
# crashed or absent listener costs latency, never mail. Links without
# alerts, paused links, and servers without IDLE are simply not watched.
class Email::IdleListener
  SUPERVISE_EVERY = 30   # seconds between supervisor sweeps
  IDLE_TIMEOUT = 600     # re-issue IDLE every 10 minutes (RFC ceiling ~29)
  ERROR_BACKOFF = 60     # seconds to sit out after a connection failure

  def initialize(client_factory: nil)
    @client_factory = client_factory || method(:build_client)
    @threads = {}
    @stopping = false
  end

  def run
    trap("TERM") { @stopping = true }
    trap("INT") { @stopping = true }
    Rails.logger.info("email-listener: starting")

    until @stopping
      supervise
      sleep SUPERVISE_EVERY
    end

    @threads.each_value { |thread| thread.kill }
    Rails.logger.info("email-listener: stopped")
  end

  # One supervisor sweep: start watchers for newly eligible links, drop
  # finished/ineligible ones. Public for tests.
  def supervise
    eligible = watchable_accounts.index_by(&:id)

    @threads.select! { |id, thread| thread.alive? && eligible.key?(id) }
    (eligible.keys - @threads.keys).each do |id|
      @threads[id] = Thread.new(eligible[id]) { |account| watch(account) }
    end
  end

  def watchable_accounts
    LinkedAccount.where(provider: "email").select do |account|
      account.setting(:alerts) == true && !account.paused? && account.allows?("read_inbox")
    end
  end

  # One blocking IDLE round for one link. Public for tests; the watcher
  # thread just loops it. => :activity | :timeout | :error | :stop
  def watch_cycle(account, client)
    account.reload
    return :stop unless account.setting(:alerts) == true && !account.paused?

    inbox = EmailFolder.inbox.find_by(linked_account_id: account.id)&.name || "INBOX"
    outcome = client.idle_wait(inbox, timeout: IDLE_TIMEOUT)
    SyncLinkedAccountJob.perform_later(account) if outcome == :activity
    outcome
  rescue Email::ImapClient::Error => e
    Rails.logger.warn("email-listener: #{account.display_name}: #{e.message}")
    :error
  rescue ActiveRecord::RecordNotFound
    :stop
  end

  private
    def watch(account)
      until @stopping
        client = @client_factory.call(account)
        begin
          loop do
            outcome = Rails.application.executor.wrap { watch_cycle(account, client) }
            return if outcome == :stop
            break if outcome == :error
          end
        ensure
          client.disconnect
        end
        sleep ERROR_BACKOFF
      end
    end

    def build_client(account)
      Email::ImapClient.new(
        host: account.credentials["host"],
        username: account.credentials["username"],
        password: account.credentials["password"])
    end
end
