# Your own photo (D-user-avatars). Always your own — there is no id in the
# route, so no member can change how another member appears, admin or not.
class AvatarsController < ApplicationController
  def update
    if avatar_param.blank?
      redirect_to settings_path, alert: "Choose an image first."
    elsif Current.user.update(avatar: avatar_param)
      redirect_to settings_path, notice: "Photo updated."
    else
      redirect_to settings_path, alert: Current.user.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.avatar.purge_later
    redirect_to settings_path, notice: "Photo removed."
  end

  private
    def avatar_param = params.dig(:user, :avatar)
end
