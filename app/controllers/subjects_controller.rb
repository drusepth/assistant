# The curriculum spine's own pages (D-education-spine): the syllabus, the
# two enrollment doors (the commons shelf and learn-anything), and the
# lifecycle verbs. Subjects are Visible like every primitive — visible_to is
# the read path, ownership gates every write.
class SubjectsController < ApplicationController
  before_action :set_own_subject, only: %i[ edit update destroy pause resume finish retry_tree ]

  def index
    redirect_to section_path("education")
  end

  def shelf
    @courses = Curriculum::Commons.all
    @enrolled_keys = Current.user.subjects.where.not(commons_key: nil).pluck(:commons_key)
  end

  def show
    @subject = Subject.visible_to(Current.user).includes(strands: :children).find(params[:id])
    @owner = @subject.user_id == Current.user.id
    @study_logs = @subject.study_logs.order(on: :desc, id: :desc).limit(8)
  end

  def new
    @subject = Current.user.subjects.new(interest_frame: params[:interest_frame])
  end

  def create
    if params[:commons_key].present?
      @subject = Curriculum::Commons.instantiate!(
        params[:commons_key], user: Current.user,
        interest_frame: subject_params[:interest_frame].presence
      )
      file_under_education(@subject)
      redirect_to @subject, notice: "Enrolled — the syllabus is yours to reshape."
    else
      @subject = Current.user.subjects.new(subject_params)
      if @subject.save
        file_under_education(@subject)
        @subject.enqueue_tree_build!
        notice = @subject.building_tree? ? "Subject added — your assistant is drafting the curriculum." : "Subject added — build the syllabus below."
        redirect_to @subject, notice: notice
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def edit
  end

  def update
    if @subject.update(subject_params)
      redirect_to @subject, notice: "Subject updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @subject.destroy!
    redirect_to section_path("education"), notice: "Subject removed. What was learned stays learned."
  end

  def pause
    @subject.paused!
    redirect_to @subject, notice: "Paused — it'll wait on the shelf."
  end

  def resume
    @subject.active!
    redirect_to @subject, notice: "Back at it."
  end

  def finish
    @subject.finished!
    redirect_to @subject, notice: "Finished — it moves to your record."
  end

  def retry_tree
    if @subject.topics.none? && @subject.generation_profile
      @subject.update_column(:tree_built_at, nil)
      GenerateSubjectTreeJob.perform_later(@subject)
      redirect_to @subject, notice: "Asking your assistant for a curriculum."
    else
      redirect_to @subject, alert: "Configure a model in Settings to generate a syllabus — or add topics by hand below."
    end
  end

  private
    def set_own_subject
      @subject = Current.user.subjects.find(params[:id])
    end

    def subject_params
      params.fetch(:subject, {}).permit(:title, :description, :interest_frame, :target_date, section_ids: [])
    end

    # Subjects default-tag Education on create (D-education-spine) — on top
    # of, never instead of, whatever else the learner tagged.
    def file_under_education(subject)
      subject.sections = (subject.sections.to_a + Section.where(slug: "education")).uniq
    end
end
