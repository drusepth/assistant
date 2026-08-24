module Diary
  # A question to start from when the page is blank — the cheapest thing
  # that turns "I should write" into writing.
  #
  # First-party strings, chosen by date arithmetic. No model call, by
  # construction rather than by policy: a prompt generated from the writer's
  # own entries would mean sending the diary to a model, and the whole
  # container exists on the premise that we never do (Q-diary-ai).
  module Prompts
    ALL = [
      "What happened today?",
      "What's taking up the most room in your head right now?",
      "Who did you talk to today, and what stayed with you?",
      "What went better than you expected?",
      "What are you putting off, and what's actually behind it?",
      "What did today cost you, and was it worth it?",
      "Describe somewhere you were today — the room, the weather, the noise.",
      "What would you tell someone who asked how you're really doing?",
      "What's something you want to remember about this week in ten years?",
      "What did you change your mind about lately?",
      "What are you looking forward to, and what's in the way?",
      "What did you do today that was just for you?",
      "Who deserves a thank-you you haven't said out loud?",
      "What felt hard today that used to feel harder?"
    ].freeze

    module_function

    # Stable for a given day, so a reload doesn't shuffle the question out
    # from under someone mid-thought.
    def for(date) = ALL[date.to_date.yday % ALL.length]
  end
end
