# One user's agent scan (D20): every watcher reads their own data and
# proposes what it finds. M3.1 hardwires the Quiet cadence — weekly, in-app
# only; per-section dials arrive in M3.2 and will filter this loop.
class AgentScanJob < ApplicationJob
  queue_as :default

  def perform(user)
    Watcher.all.each { |watcher| watcher.new(user).scan }
  end
end
