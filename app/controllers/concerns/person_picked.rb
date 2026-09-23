# The answer to a person picker (D-person-picker): whoever was just put in
# the circle or a group. Filling a circle is five or ten names in a row, so
# a form that asked for it (`inline`) is answered in place — the new face
# lands on the card, the notice says so with an Undo, the field keeps the
# cursor — instead of a reload that loses your place after every name.
# Everything else (the person page's buttons, no JS) gets the redirect it
# always did, carrying the same Undo.
module PersonPicked
  extend ActiveSupport::Concern

  private
    # `created` is whether the person was made from the typed name just
    # now — a bare name is a thin contact, so the notice offers the next
    # step. The block returns the page-specific streams.
    def person_picked(person, created:, notice:, undo_url:, fallback:)
      undo = { "label" => "Undo", "url" => undo_url, "method" => "delete" }
      follow_up = { "label" => "Add a birthday or phone", "url" => edit_person_path(person) } if created

      if params[:inline].present? && request.format.turbo_stream?
        flash.now[:notice] = notice
        flash.now[:undo] = undo
        flash.now[:follow_up] = follow_up if follow_up
        render turbo_stream: [
          turbo_stream.update("flash", html: view_context.render(Ui::FlashComponent.new(flash: flash))),
          *yield
        ]
      else
        flash[:undo] = undo
        flash[:follow_up] = follow_up if follow_up
        redirect_back fallback_location: fallback, notice: notice
      end
    end

    # The circle and group cards on the People page, redrawn from the same
    # service that drew them.
    def people_cards
      @people_cards ||= People::Circles.for(Current.user, Section.find_by!(slug: "people"))
    end

    def card_summary_stream(card)
      turbo_stream.replace("#{card.dom_id}-summary", partial: "sections/circle_card_summary", locals: { card: card })
    end
end
