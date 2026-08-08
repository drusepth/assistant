# Photo ingestion (D-photos-primitive): deterministic and LLM-free — EXIF capture
# time/location into columns, then the WEBP variants pre-rendered so the
# grid and lightbox never block on first view.
class IngestPhotoJob < ApplicationJob
  queue_as :default

  def perform(photo)
    return unless photo.image.attached?

    photo.update!(ingest_status: :processing)

    exif = photo.image.blob.open { |file| Photos::Exif.read(file.path) }
    photo.update!(
      taken_at: exif.taken_at || photo.taken_at,
      latitude: exif.latitude,
      longitude: exif.longitude
    )

    photo.image.variant(:thumb).processed
    photo.image.variant(:large).processed

    photo.update!(ingest_status: :ready, ingest_error: nil)
  rescue StandardError => e
    # Don't leave the photo stuck in "processing", but let the error reach
    # the job backend's log too (the AnalyzeDocumentJob convention).
    photo.update!(ingest_status: :failed, ingest_error: "Couldn't process this image — is it a supported format?")
    record_failure(e, user: photo.user, context: { photo_id: photo.id })
    raise
  end
end
