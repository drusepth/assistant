class CaptionPhotoJob < ApplicationJob
  include RetriesModelCalls

  queue_as :default

  def perform(photo)
    profile = photo.captionable_profile
    return unless profile

    photo.update!(caption_status: :processing)
    result = Photos::Caption.new(photo: photo, profile: profile).call
    photo.update!(
      caption: result.caption,
      suggested_sections: result.section_slugs,
      caption_status: :captioned,
      caption_error: nil
    )
    # Untagged photos get filed automatically (D16); once the user has
    # tagged one themselves, suggestions stay suggest-and-click.
    photo.sections = photo.suggested_section_records if photo.sections.none?
  rescue Llm::Error => e
    raise if will_retry?(e)

    photo.update!(caption_status: :failed, caption_error: e.message)
    record_failure(e, user: photo.user, context: { photo_id: photo.id })
  rescue StandardError => e
    photo.update!(caption_status: :failed, caption_error: "Something went wrong describing this photo — try again.")
    record_failure(e, user: photo.user, context: { photo_id: photo.id })
    raise
  end
end
