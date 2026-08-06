# The weekly tick (config/recurring.yml): one job per user, so a slow scan
# for one household member never blocks another's.
class AgentScanFanoutJob < ApplicationJob
  queue_as :default

  def perform
    User.find_each { |user| AgentScanJob.perform_later(user) }
  end
end
