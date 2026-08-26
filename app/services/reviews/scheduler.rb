module Reviews
  # The spaced-repetition brain (D-review-scheduler): FSRS-4.5 with its
  # published default parameters — pure deterministic arithmetic, no model
  # call anywhere. The model may *write* cards and a conversation may *mint*
  # them, but when a card comes back is decided here and only here. Nothing
  # else in the app writes the memory-state columns.
  #
  # The shape follows the open algorithm (github.com/open-spaced-repetition):
  # each card carries a difficulty D (1..10) and a stability S (days until
  # retrievability falls to 90%); a grade updates both and the next interval
  # targets DESIRED_RETENTION. Sub-day learning steps are collapsed to one
  # honest "again ≈ 10 minutes" step — this is a daily habit on a phone, not
  # a cram machine.
  module Scheduler
    # FSRS-4.5 default weights. Per-learner optimization needs hundreds of
    # reviews of history (Q-education-fsrs-tuning) — defaults until then.
    W = [ 0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,
          1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755 ].freeze

    DESIRED_RETENTION = 0.9
    DECAY = -0.5
    FACTOR = (19.0 / 81.0)
    AGAIN_STEP = 10.minutes
    MAX_INTERVAL_DAYS = 36_500
    RATINGS = { "again" => 1, "hard" => 2, "good" => 3, "easy" => 4 }.freeze

    module_function

    # Apply one graded recall to a card. `rating` is again/hard/good/easy.
    def grade!(item, rating, now: Time.current)
      grade = RATINGS.fetch(rating.to_s) { raise ArgumentError, "unknown rating #{rating.inspect}" }

      if item.fresh? || item.stability.nil?
        first_grade(item, grade, now)
      elsif grade == 1
        lapse(item, grade, now)
      else
        recall(item, grade, now)
      end
      item.update!(reps: item.reps + 1, last_reviewed_at: now)
      item
    end

    # What each button would mean, for honest labels on the quartet — the
    # same arithmetic run without persisting.
    def preview(item, now: Time.current)
      RATINGS.keys.index_with do |rating|
        interval_label(simulated_due(item, RATINGS[rating], now), now)
      end
    end

    def simulated_due(item, grade, now)
      return now + AGAIN_STEP if grade == 1

      if item.fresh? || item.stability.nil?
        now + next_interval(W[grade - 1].clamp(0.1, MAX_INTERVAL_DAYS)).days
      elsif item.review?
        retention = retrievability(item, now: now) || DESIRED_RETENTION
        now + next_interval(recall_stability(item.difficulty, item.stability, retention, grade)).days
      else
        now + next_interval(item.stability).days
      end
    end

    # Predicted probability of recall right now — what the rusty sweep reads.
    def retrievability(item, now: Time.current)
      return nil if item.stability.blank? || item.last_reviewed_at.blank?

      elapsed_days = [ (now - item.last_reviewed_at) / 1.day, 0.0 ].max
      (1 + FACTOR * elapsed_days / item.stability)**DECAY
    end

    # ── the FSRS arithmetic ──────────────────────────────────────────────

    def first_grade(item, grade, now)
      stability = W[grade - 1].clamp(0.1, MAX_INTERVAL_DAYS)
      difficulty = init_difficulty(grade)
      if grade == 1
        item.update!(state: :learning, stability: stability, difficulty: difficulty,
          due_at: now + AGAIN_STEP, lapses: item.lapses)
      else
        item.update!(state: :review, stability: stability, difficulty: difficulty,
          due_at: now + next_interval(stability).days)
      end
    end

    def recall(item, grade, now)
      if item.review?
        retention = retrievability(item, now: now) || DESIRED_RETENTION
        item.stability = recall_stability(item.difficulty, item.stability, retention, grade)
        item.difficulty = next_difficulty(item.difficulty, grade)
      end
      # Graduating from (re)learning keeps the stability the lapse or first
      # grade set — the sub-day steps are collapsed on purpose.
      item.update!(state: :review, stability: item.stability, difficulty: item.difficulty,
        due_at: now + next_interval(item.stability).days)
    end

    def lapse(item, _grade, now)
      retention = retrievability(item, now: now) || DESIRED_RETENTION
      item.update!(
        state: :relearning,
        stability: forget_stability(item.difficulty, item.stability, retention),
        difficulty: next_difficulty(item.difficulty, 1),
        lapses: item.lapses + 1,
        due_at: now + AGAIN_STEP
      )
    end

    def init_difficulty(grade) = (W[4] - (grade - 3) * W[5]).clamp(1.0, 10.0)

    def next_difficulty(difficulty, grade)
      moved = difficulty - W[6] * (grade - 3)
      (W[7] * init_difficulty(4) + (1 - W[7]) * moved).clamp(1.0, 10.0)
    end

    def recall_stability(difficulty, stability, retention, grade)
      hard_penalty = grade == 2 ? W[15] : 1.0
      easy_bonus = grade == 4 ? W[16] : 1.0
      growth = Math.exp(W[8]) * (11 - difficulty) * stability**-W[9] *
        (Math.exp(W[10] * (1 - retention)) - 1) * hard_penalty * easy_bonus
      (stability * (growth + 1)).clamp(0.1, MAX_INTERVAL_DAYS)
    end

    def forget_stability(difficulty, stability, retention)
      forgotten = W[11] * difficulty**-W[12] * ((stability + 1)**W[13] - 1) *
        Math.exp(W[14] * (1 - retention))
      forgotten.clamp(0.1, stability)
    end

    def next_interval(stability)
      ((stability / FACTOR) * (DESIRED_RETENTION**(1 / DECAY) - 1)).round.clamp(1, MAX_INTERVAL_DAYS)
    end

    def interval_label(due_at, now)
      minutes = ((due_at - now) / 60).round
      return "#{minutes} min" if minutes < 90

      days = ((due_at - now) / 1.day).round
      return "#{days} d" if days < 30
      return "#{(days / 30.4).round} mo" if days < 365

      "#{(days / 365.0).round(1)} yr"
    end
  end
end
