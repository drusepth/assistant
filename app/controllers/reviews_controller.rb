# The daily queue (D-review-scheduler): one card at a time, one thumb,
# interleaved across subjects by construction. Grading is the learner's own
# (Again/Hard/Good/Easy — no model anywhere in the loop), the schedule is
# FSRS arithmetic, and a rusty topic that answers clean re-earns its green.
class ReviewsController < ApplicationController
  def show
    Reviews::RustySweep.run(Current.user)
    @due_count = Current.user.review_items.due.count
    @item = Current.user.review_items.due.queue_order.includes(topic: :subject).first
    @preview = @item && Reviews::Scheduler.preview(@item)
  end

  def grade
    item = Current.user.review_items.find(params[:id])
    Reviews::Scheduler.grade!(item, params[:rating])
    shore_up_if_recovered(item, params[:rating])
    bump_study_log(item)
    redirect_to reviews_path
  rescue ArgumentError
    redirect_to reviews_path, alert: "That's not a grade."
  end

  private
    # Clean recall on the last due card of a rusty topic is the shore-up
    # (D-mastery-evidence): same evidence door, minutes not months.
    def shore_up_if_recovered(item, rating)
      return unless %w[ good easy ].include?(rating.to_s)

      topic = item.topic
      return unless topic.rusty?

      topic.shore_up! if topic.review_items.due.none?
    end

    # The durable minutes (D-learning-record), measured rather than guessed:
    # each grade extends the day's review log by the real gap since the last
    # one, capped so walking away doesn't bill the afternoon.
    def bump_study_log(item)
      subject = item.topic.subject
      log = Current.user.study_logs.where(activity: :review, subject: subject, on: Date.current)
        .order(:updated_at).last

      if log && log.updated_at > 15.minutes.ago
        elapsed = ((Time.current - log.updated_at) / 60.0).round.clamp(0, 5)
        log.update!(minutes: log.minutes + elapsed) if elapsed.positive?
        log.touch if elapsed.zero?
      elsif log.nil? || log.updated_at <= 15.minutes.ago
        Current.user.study_logs.create!(subject: subject, activity: :review, on: Date.current, minutes: 1)
      end
    end
end
