# The two one-tap capture verbs of the career signal (D30, docs/CAREER.md
# §1): a win-log line and a comp-change entry, landing as ordinary
# Career-tagged primitives — the receipts the raise tools read later.
class CareerController < ApplicationController
  def create_win
    Career::WinLog.log!(user: Current.user, text: params[:text])
    redirect_to section_path("career"), notice: "Win logged. It'll be there when you build the raise case."
  rescue ArgumentError
    redirect_to section_path("career"), alert: "A win needs a line."
  end

  def create_comp_change
    Career::CompChange.log!(user: Current.user, summary: params[:summary], on: comp_change_date)
    redirect_to section_path("career"), notice: "Pay change logged — raise cadence measures from here."
  rescue ArgumentError
    redirect_to section_path("career"), alert: "Describe the change — like “Raise: $19 → $21/hr”."
  end

  private
    def comp_change_date
      Date.iso8601(params[:on].to_s)
    rescue Date::Error
      Date.current
    end
end
