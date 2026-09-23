# Drag to reschedule: an event or task dropped on another day of the
# calendar. Only your own — the same rule the edit forms keep — and only the
# day moves: an event keeps its clock time and its length, so dragging
# Tuesday's 3pm haircut to Thursday makes it Thursday's 3pm haircut.
# Relative reminders follow on their own (Remindable resyncs after commit).
class CalendarMovesController < ApplicationController
  def create
    date = Date.iso8601(params[:date].to_s)
    record = move(params[:kind], date)
    flash[:notice] = "“#{record.title.truncate(48)}” moved to #{date.strftime("%a %b %-d")}."
    head :no_content
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    flash[:alert] = "Couldn't move that: #{error.message}"
    head :unprocessable_entity
  end

  private
    def move(kind, date)
      case kind
      when "event"
        event = Current.user.events.find(params[:id])
        shift = (date - event.starts_at.to_date).to_i
        event.update!(starts_at: event.starts_at.advance(days: shift), ends_at: event.ends_at&.advance(days: shift))
        event
      when "task"
        task = Current.user.tasks.find(params[:id])
        task.update!(due_on: date)
        task
      else
        raise ArgumentError, "not something that moves"
      end
    end
end
