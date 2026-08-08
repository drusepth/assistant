# Refreshes the D31 public datasets from BLS. Fired from the /admin button
# (and safe to wire to a recurring schedule); partial failures are recorded
# per dataset, never raised — an unreachable bls.gov leaves the current
# files exactly as they were.
class RefreshDatasetsJob < ApplicationJob
  queue_as :default

  def perform
    result = Datasets::Refresh.new.call
    result.errors.each do |dataset, message|
      AppError.record(StandardError.new(message), source: "dataset_refresh:#{dataset}")
    end
  end
end
