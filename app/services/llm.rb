module Llm
  # Base for everything the model layer raises. Callers that don't care why a
  # model call failed — most of them — rescue this.
  #
  # Treated as *permanent* by the retry policy (RetriesModelCalls), which is
  # the safe default: tools raise a bare Llm::Error for conditions that will
  # never fix themselves ("no model configured", "that document is gone"), and
  # retrying those four times just delays an honest failure.
  class Error < StandardError; end

  # Worth trying again: the request was fine, the provider just couldn't answer
  # right now — a timeout, a dropped connection, a 429, a 502. Only Llm::Client
  # raises this, and only where it can tell the difference.
  class TransientError < Error; end
end
