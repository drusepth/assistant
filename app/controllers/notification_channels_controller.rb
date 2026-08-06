class NotificationChannelsController < ApplicationController
  def create
    channel = Current.user.notification_channels.new(channel_attributes)

    respond_to do |format|
      if channel.save
        format.html { redirect_to settings_path, notice: "Notification channel added." }
        format.json { head :created }
      else
        format.html { redirect_to settings_path, alert: channel.errors.full_messages.to_sentence }
        format.json { render json: { errors: channel.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    Current.user.notification_channels.find(params[:id]).destroy!
    redirect_to settings_path, notice: "Notification channel removed."
  end

  private
    def channel_attributes
      case params.expect(:kind)
      when "webhook" then { kind: :webhook, config: { "url" => params[:url].to_s.strip } }
      when "email" then { kind: :email, config: { "address" => params[:address].to_s.strip } }
      when "web_push" then { kind: :web_push, config: { "subscription" => subscription_params } }
      else raise ActionController::BadRequest, "unknown channel kind"
      end
    end

    def subscription_params
      params.expect(subscription: [ :endpoint, keys: %i[ p256dh auth ] ]).to_h
    end
end
