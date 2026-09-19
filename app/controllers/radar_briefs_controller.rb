# The radar's two sentences (D-event-radar §5.1): what else the household
# would go to, and what this person would give time to. A sentence and a
# button, on the user's own row; changing one is a question about the
# listings already here, so it re-sweeps.
class RadarBriefsController < ApplicationController
  def update
    changes = params.permit(:radar_brief, :causes_brief).to_h.transform_values { |value| value.to_s.squish.presence }
    return back(alert: "Keep it under #{Radar::Briefs::MAX_LENGTH} characters.") if changes.values.any? { |value| value.to_s.length > Radar::Briefs::MAX_LENGTH }

    Current.user.update!(changes)
    resweep if changes.any?
    back notice: "Saved."
  end

  # "Suggest a sentence" — one model call, asked for out loud.
  def author
    if Radar::Briefs.enqueue(Current.user, params[:kind].to_s)
      back notice: "Reading what you follow for a sentence…"
    else
      back alert: "No model is configured, so this one is yours to write."
    end
  end

  private
    def resweep
      Radar::Match.resweep!(Current.user)
      Radar::Match.enqueue(Current.user)
    end

    def back(notice: nil, alert: nil)
      redirect_back fallback_location: places_path, notice: notice, alert: alert
    end
end
