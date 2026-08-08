require "test_helper"

# The IDLE listener's decision logic (E6). The thread supervisor is thin
# on purpose; what's tested is who gets watched and what a cycle does.
class Email::IdleListenerTest < ActiveSupport::TestCase
  class ScriptedClient
    attr_reader :idled

    def initialize(outcomes) = (@outcomes = outcomes; @idled = 0)

    def idle_wait(_folder, timeout: nil)
      @idled += 1
      outcome = @outcomes.shift or raise Email::ImapClient::Error, "script exhausted"
      raise Email::ImapClient::Error, "connection dropped" if outcome == :raise
      outcome
    end

    def disconnect = nil
  end

  setup do
    @account = linked_accounts(:alice_email)
    @listener = Email::IdleListener.new(client_factory: ->(_account) { raise "unused" })
  end

  test "only alert-enabled, unpaused links are watched" do
    assert_empty @listener.watchable_accounts, "alerts are off by default"

    @account.update!(settings: { "alerts" => true })
    assert_equal [ @account ], @listener.watchable_accounts

    @account.update!(settings: { "alerts" => true, "paused" => true })
    assert_empty @listener.watchable_accounts

    @account.update!(settings: { "alerts" => true }, disabled_scopes: [ "read_inbox" ])
    assert_empty @listener.watchable_accounts, "no read scope, no watching"
  end

  test "a signal enqueues the ordinary sync job; a quiet timeout doesn't" do
    @account.update!(settings: { "alerts" => true })
    client = ScriptedClient.new([ :activity, :timeout ])

    assert_enqueued_with(job: SyncLinkedAccountJob, args: [ @account ]) do
      assert_equal :activity, @listener.watch_cycle(@account, client)
    end

    assert_no_enqueued_jobs(only: SyncLinkedAccountJob) do
      assert_equal :timeout, @listener.watch_cycle(@account, client)
    end
  end

  test "turning the dial off stops the watcher; connection failures back off as errors" do
    @account.update!(settings: { "alerts" => true })
    client = ScriptedClient.new([ :raise ])
    assert_equal :error, @listener.watch_cycle(@account, client)

    @account.update!(settings: {})
    assert_equal :stop, @listener.watch_cycle(@account, client)
    assert_equal 1, client.idled, "a stopped link never touches the connection again"
  end

  include ActiveJob::TestHelper
end
