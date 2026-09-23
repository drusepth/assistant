# Minting and revoking the read-only public links (D-share-link). Only the
# owner of an allowlisted subject can create one, and revoking is deleting
# the row — there is no state in which a link half-works.
class ShareLinksController < ApplicationController
  def create
    link = Current.user.share_links.new(
      subject: find_subject,
      label: params[:label].presence,
      expires_at: ShareLink.expiry_from(params[:expires_in_days])
    )

    if link.save
      redirect_back fallback_location: link.subject, notice: "Link created — anyone with it can read this."
    else
      redirect_back fallback_location: recipes_path, alert: link.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.share_links.find(params[:id]).destroy!
    redirect_back fallback_location: recipes_path, notice: "Link revoked."
  end

  private
    # A fixed lookup, never reflection on params: this is the one public
    # read path in the app and the allowlist is what keeps it narrow.
    def find_subject
      klass = [ Recipe, RecipeBook, Album, Pet ].find { |candidate| candidate.name == params[:subject_type] }
      raise ActiveRecord::RecordNotFound if klass.nil?

      Current.user.public_send(klass.name.underscore.pluralize).find(params[:subject_id])
    end
end
