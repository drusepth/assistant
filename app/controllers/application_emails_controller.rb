# The ask half of ask-then-send (D-career-web): the compose form on a
# Tailor-my-application run IS the review — the user sees and edits exactly
# what goes out, then clicks Send. On success the application lands on the
# record: an Applied event on the calendar and a follow-up task, both on
# the run.
class ApplicationEmailsController < ApplicationController
  def create
    run = Current.user.tool_runs.find(params[:tool_run_id])
    Career::EmailApply.new(
      user: Current.user,
      to: params[:to], subject: params[:subject], body: params[:body],
      resume: resume_document
    ).call

    record_application(run)
    redirect_to run, notice: "Application sent to #{params[:to]} — logged on your calendar with a follow-up task."
  rescue Career::EmailApply::Error => e
    redirect_to run, alert: e.message
  end

  private
    def resume_document
      return nil if params[:resume_document_id].blank?

      Document.visible_to(Current.user).find_by(id: params[:resume_document_id])
    end

    def record_application(run)
      role = run.inputs["role"].presence || "the role"
      career = Section.where(slug: "career")

      event = Current.user.events.create!(
        title: "Applied: #{role}", starts_at: Time.current, all_day: true,
        description: "Sent by email to #{params[:to]} from your linked address."
      )
      event.sections = career
      run.tool_run_items.create!(item: event)

      task = Current.user.tasks.create!(title: "Follow up on application: #{role}", due_on: 10.days.from_now.to_date)
      task.sections = career
      run.tool_run_items.create!(item: task)
    end
end
