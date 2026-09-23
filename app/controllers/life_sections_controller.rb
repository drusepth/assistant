# The "Your life" picker (D-section-picker): one card per top-level section,
# each switched on or off on its own. The same `user_sections.enabled` the
# Settings card writes — this is a page for choosing, that one is for
# ordering and agent dials — so the two can never disagree.
class LifeSectionsController < ApplicationController
  def index
    @sections = Current.user.ordered_sections
    @disabled_ids = Current.user.user_sections.where(enabled: false).pluck(:section_id).to_set
  end

  def update
    section = Section.top_level.find_by!(slug: params[:slug])
    enabled = params[:enabled] == "1"
    Current.user.user_sections.find_or_initialize_by(section: section).update!(enabled: enabled)

    # A redirect to the page you're on is a Turbo refresh, which morphs —
    # so the card flips and the sidebar gains or loses the row in place.
    redirect_to life_sections_path, notice: enabled ?
      "#{section.name} is on — it's in your sidebar." :
      "#{section.name} is off. Nothing in it was deleted; turn it back on any time."
  end
end
