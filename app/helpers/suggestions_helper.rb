module SuggestionsHelper
  # The accept button says what accepting does (D20: acceptance is one
  # explicit, legible click) — labels grow with the action types.
  def suggestion_accept_label(suggestion)
    case suggestion.action["type"]
    when "create_event" then "Put it on the calendar"
    else "Do it"
    end
  end
end
