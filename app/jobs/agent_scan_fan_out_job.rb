# The recurring entry point (config/recurring.yml): fans one scan job out
# per user. M3.1 hardwires the Quiet dial — weekly, in-app only; per-section
# dials arrive with M3.2 and will move cadence decisions in here.
class AgentScanFanOutJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each { |user| AgentScanJob.perform_later(user) }
  end
end
