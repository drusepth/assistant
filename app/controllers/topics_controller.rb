# Tree surgery and the mastery door. Every action is owner-only through the
# subject — a topic has no visibility of its own; it travels with its
# subject's grant (D-education-spine).
class TopicsController < ApplicationController
  before_action :set_topic, except: :create

  def create
    subject = Current.user.subjects.find(params[:topic][:subject_id])
    attrs = topic_params
    attrs[:position] = subject.topics.where(parent_id: attrs[:parent_id].presence).maximum(:position).to_i + 1
    topic = subject.topics.new(attrs)
    if topic.save
      redirect_to subject, notice: "Topic added."
    else
      redirect_to subject, alert: topic.errors.full_messages.to_sentence
    end
  end

  def update
    if @topic.update(topic_params.except(:parent_id))
      redirect_to @topic.subject, notice: "Topic updated."
    else
      redirect_to @topic.subject, alert: @topic.errors.full_messages.to_sentence
    end
  end

  def destroy
    subject = @topic.subject
    @topic.destroy!
    redirect_to subject, notice: "Topic removed."
  end

  # Manual marking (D-mastery-evidence): the learner's own say-so is allowed
  # — their school, their record — but recorded as self-marked. Tools write
  # stronger evidence through Topic#advance! directly.
  def mastery
    state = params[:state].to_s
    if Topic.masteries.key?(state)
      @topic.advance!(to: state, evidence: "self_marked")
      redirect_to @topic.subject, notice: mastery_notice(state)
    else
      redirect_to @topic.subject, alert: "That's not a mastery state."
    end
  end

  # Swap positions with the neighbor above or below, within the same parent.
  def move
    siblings = @topic.subject.topics.where(parent_id: @topic.parent_id).ordered.to_a
    index = siblings.index(@topic)
    neighbor = params[:direction] == "up" ? (index.positive? ? siblings[index - 1] : nil) : siblings[index + 1]
    if neighbor
      Topic.transaction do
        @topic.position, neighbor.position = neighbor.position, @topic.position
        @topic.save!
        neighbor.save!
      end
    end
    redirect_to @topic.subject
  end

  # The Learn-something bridge: studying a topic spawns a Goal broken into
  # day-sized Tasks, so Today keeps pulling the learner back.
  def plan
    if @topic.goal&.active?
      redirect_to @topic.goal, notice: "This topic already has a plan."
    else
      goal = Current.user.goals.create!(
        title: "Study #{@topic.title}",
        description: [ @topic.subject.title, @topic.summary ].compact_blank.join(" — ")
      )
      goal.sections = (@topic.subject.sections.to_a + Section.where(slug: "education")).uniq
      @topic.update!(goal: goal)
      goal.enqueue_break_down!
      notice = goal.breaking_down? ? "Planning steps for “#{@topic.title}”." : "Goal added for “#{@topic.title}” — add its steps on the board."
      redirect_to @topic.subject, notice: notice
    end
  end

  private
    def set_topic
      @topic = Topic.joins(:subject).where(subjects: { user_id: Current.user.id }).find(params[:id])
    end

    def topic_params
      params.expect(topic: [ :title, :summary, :parent_id ])
    end

    def mastery_notice(state)
      case state
      when "mastered" then "Marked mastered — noted as your own call."
      when "unseen" then "Reset to not started."
      else "Marked #{state.humanize.downcase}."
      end
    end
end
