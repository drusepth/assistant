# The allergies card's add form (docs/HEALTH.md §8): an allergy is a Note
# (kind: allergy) — the allergen as title, the reaction as body — carrying a
# severity, filed under Health. No new primitive, so it exports, shares, and
# reaches the tools like every other note; what it adds over a plain note is
# the one field a clinician asks for first.
class AllergiesController < ApplicationController
  def create
    allergen = params[:allergen].to_s.squish
    if allergen.blank?
      return redirect_to section_path("health"), alert: "An allergy needs something you're allergic to."
    end

    note = Current.user.notes.create!(
      kind: Note::ALLERGY,
      title: allergen,
      body: params[:reaction].to_s.squish.presence || allergen,
      severity: params[:severity].to_s.presence_in(Note::SEVERITIES)
    )
    note.sections = [ health_section ].compact

    redirect_to section_path("health"), notice: "#{allergen} added to your allergies."
  end

  # Allergies are outgrown and misremembered, so the card that adds one
  # removes it too — the note page can do this as well, but the list you are
  # looking at is where you notice it's wrong.
  def destroy
    note = Current.user.notes.allergies.find(params[:id])
    note.destroy!

    redirect_to section_path("health"), notice: "#{note.title} removed from your allergies."
  end

  private
    def health_section = Section.find_by(slug: "health")
end
