# Quick-added items get filed by the household's model instead of a form
# (D16). Including models define AUTO_SORT_JOB, the job that does the filing.
module AutoSortable
  extend ActiveSupport::Concern

  # Items the user tagged by hand are left alone — auto-sorting only ever
  # fills a blank slate.
  def enqueue_auto_sort!
    return if sections.any?
    return unless auto_sort_profile

    self.class::AUTO_SORT_JOB.perform_later(self)
  end

  def auto_sort_profile
    profile = user.household.model_profile
    profile if profile&.configured?
  end
end
