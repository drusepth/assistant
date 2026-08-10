module DashboardHelper
  # The runtime card's second line (design 2a). Three facts, in the order
  # that matters to someone who chose to self-host: where the model runs,
  # then when the assistant last looked at their data.
  #
  # "Local" is claimed only for a custom endpoint pointed at a host we can
  # see is this machine. Everything else is named as what it is — an app
  # whose whole pitch is ownership must not imply local processing while a
  # key ships text to a vendor.
  LOCAL_HOSTS = %w[localhost 127.0.0.1 0.0.0.0 ::1 host.docker.internal].freeze

  def runtime_line
    [ model_phrase, scan_phrase ].compact.join(" · ")
  end

  private
    def model_phrase
      profile = Current.user.household.model_profile
      return "No model configured yet" unless profile&.configured?

      # display_name already parenthesises the model for some providers
      # ("OpenAI (gpt-4o)"), so the remote marker leads instead of trailing —
      # "Remote model — OpenAI (gpt-4o)" rather than a doubled paren.
      local_model?(profile) ? "Local model — #{profile.display_name}" : "Remote model — #{profile.display_name}"
    end

    def local_model?(profile)
      profile.provider == "custom" && LOCAL_HOSTS.include?(profile.endpoint_host)
    end

    def scan_phrase
      last = Current.user.digest_generated_at
      last ? "last scan #{time_ago_in_words(last)} ago" : "first weekly scan still to come"
    end
end
