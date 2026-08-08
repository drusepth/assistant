# The medications card's add form (docs/HEALTH.md §7): a medication is a
# Note (kind: medication) — name as title, dose/schedule as body — plus an
# optional all-day refill Event. Both file under Health; the refill event
# is care_kind "none" so the radar never mistakes a refill for a visit,
# and the renewal-radar watcher gives it lead time like any renewal.
class MedicationsController < ApplicationController
  def create
    name = params[:name].to_s.squish
    if name.blank?
      return redirect_to section_path("health"), alert: "A medication needs a name."
    end

    note = Current.user.notes.create!(
      kind: Note::MEDICATION,
      title: name,
      body: params[:details].to_s.squish.presence || name
    )
    note.sections = [ health_section ].compact

    if (refill_on = parsed_date(params[:refill_on]))
      event = Current.user.events.create!(
        title: "Refill #{name}", starts_at: refill_on.in_time_zone, all_day: true,
        care_kind: Health::CareRadar::EXCLUDED
      )
      event.sections = [ health_section ].compact
    end

    redirect_to section_path("health"), notice: "#{name} added to your medications."
  end

  private
    def health_section = Section.find_by(slug: "health")

    def parsed_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
end
