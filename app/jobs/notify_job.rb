class NotifyJob < ApplicationJob
  queue_as :default

  def perform(user, titles)
    Notifications::Deliver.new(user, titles: titles).call
  end
end
