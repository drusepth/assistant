# The feedback loop's write path (EMAIL_PLAN.md §6): one click on a
# digest row or alert teaches a deterministic sender rule. Rules are the
# user's own, listed and removable in Settings (D9).
class EmailSenderRulesController < ApplicationController
  def create
    rule = Current.user.email_sender_rules.find_or_initialize_by(email: params[:email].to_s.downcase.strip)
    rule.rule = params[:rule]
    if rule.save
      verb = rule.rule == "mute" ? "won't be surfaced" : "will always be treated as important"
      redirect_back fallback_location: root_path, notice: "Got it — mail from #{rule.email} #{verb}. Change this any time in Settings."
    else
      redirect_back fallback_location: root_path, alert: rule.errors.full_messages.to_sentence
    end
  end

  def destroy
    rule = Current.user.email_sender_rules.find(params[:id])
    rule.destroy!
    redirect_to settings_path, notice: "Rule for #{rule.email} removed."
  end
end
