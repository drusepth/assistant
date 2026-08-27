module Notes
  # "Quiz me on this" on a note page (D-note-quiz). One POST: bind a
  # quiz_note run to the note, enqueue the opening question, and hand the
  # user the run page where the conversation happens. No form, because
  # there is nothing left to ask — the note *is* the input (D16).
  #
  # Notes shared with you count: being quizzed on a study partner's note is
  # the same act as reading it. Runs stay private to whoever took them.
  class QuizzesController < ApplicationController
    def create
      note = Note.visible_to(Current.user).find(params[:note_id])
      run = Current.user.tool_runs.create!(tool_slug: "quiz_note", subject: note)
      ToolRunJob.perform_later(run)
      redirect_to run
    end
  end
end
