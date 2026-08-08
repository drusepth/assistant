# The seventh primitive (D30): high-volume visual items with their own
# capture date and browsing idiom. Originals are never modified — the grid
# and lightbox run on derived WEBP variants with metadata stripped, so a
# shared viewer never receives the original's EXIF.
class Photo < ApplicationRecord
  include Visible
  include Sectionable

  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 400, 400 ], format: :webp,
      saver: { quality: 80, strip: true }
    attachable.variant :large, resize_to_limit: [ 1600, 1600 ], format: :webp,
      saver: { quality: 85, strip: true }
  end

  enum :ingest_status, {
    queued: "queued", processing: "processing", ready: "ready", failed: "failed"
  }, prefix: :ingest

  validate :image_must_be_attached_and_an_image, on: :create

  # The timeline needs an order the moment the row exists; ingestion
  # replaces this with the EXIF capture time when the photo has one.
  before_validation { self.taken_at ||= Time.current }

  def display_title
    title.presence || taken_at.strftime("%B %-d, %Y")
  end

  # Same bytes, same person, already in the library (D30 dedupe): matched by
  # the blob checksum Active Storage computed at upload. Only older rows
  # count — of two identical copies, the first stays and the second is the
  # duplicate.
  def duplicate_of_existing?
    return false unless image.attached?

    Photo.where(user_id: user_id).where(id: ...id)
      .joins(image_attachment: :blob)
      .exists?(active_storage_blobs: { checksum: image.blob.checksum })
  end

  def enqueue_ingest!
    update!(ingest_status: :queued, ingest_error: nil)
    IngestPhotoJob.perform_later(self)
  end

  def coordinates? = latitude.present? && longitude.present?

  private
    def image_must_be_attached_and_an_image
      return errors.add(:image, "must be attached") unless image.attached?

      unless image.blob.content_type.to_s.start_with?("image/")
        errors.add(:image, "must be an image")
      end
    end
end
