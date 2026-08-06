# The retry policy for every job that talks to a model.
#
# Model calls fail in two very different ways and only one is worth trying
# again: a timeout or a 429 usually clears on its own, while a bad API key or a
# missing document fails identically forever. Llm::Client draws that line
# (Llm::TransientError vs a plain Llm::Error); this turns it into behavior.
#
# Including jobs keep their own `rescue Llm::Error` and open it with
# `raise if will_retry?(e)` — re-raising hands the error to retry_on, and
# falling through means this was the last attempt, so the job does what it
# always did: leave the item unsorted, mark the run failed, record it for
# /admin. Because a job stops re-raising on its final attempt, retry_on's
# exhaustion path is never reached and no model failure ever escapes to the
# job backend.
module RetriesModelCalls
  extend ActiveSupport::Concern

  # Roughly 3s, 18s, and 83s apart with :polynomially_longer — long enough to
  # outlast a rate-limit window without leaving a person staring at a spinner
  # for the better part of an hour.
  ATTEMPTS = 4

  included do
    retry_on Llm::TransientError, wait: :polynomially_longer, attempts: ATTEMPTS
  end

  private
    # True while another attempt is still coming. `executions` counts the run
    # in progress, so on the final attempt this is false and the caller is free
    # to write the failure down — and to show it to the user. Also keeps
    # ApplicationJob's safety net from logging one AppError per attempt.
    def will_retry?(error)
      error.is_a?(Llm::TransientError) && executions < ATTEMPTS
    end
end
