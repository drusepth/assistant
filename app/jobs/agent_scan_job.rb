# One user's agent scan (D20): wake expired snoozes, then let every watcher
# look. Deterministic and cheap — no model calls — so running it for a user
# with nothing to notice costs a handful of SQL queries.
class AgentScanJob < ApplicationJob
  queue_as :default

  def perform(user)
    user.suggestions.wake_expired_snoozes!
    Watcher.all.each { |watcher| watcher.new(user).scan }
  end
end
