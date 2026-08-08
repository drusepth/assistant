# The seventh primitive (D31): high-volume visual items with their own
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

  has_many :album_photos, dependent: :destroy
  has_many :albums, through: :album_photos
  has_many :photo_people, dependent: :destroy
  has_many :people, through: :photo_people

  # The album sharing path (D31): a grant on a containing album exposes the
  # photo — but only when the grant's grantor owns the photo, so a future
  # collaborative album (Q15) can never leak a contributor's photo through
  # someone else's grant.
  def self.extra_visibility_clauses
    [ <<~SQL ]
      EXISTS (
        SELECT 1 FROM access_grants
        INNER JOIN album_photos
          ON album_photos.album_id = access_grants.subject_id
          AND album_photos.photo_id = photos.id
        WHERE access_grants.grantee_id = :viewer_id
          AND access_grants.subject_type = 'Album'
          AND access_grants.grantor_id = photos.user_id
      )
    SQL
  end

  enum :ingest_status, {
    queued: "queued", processing: "processing", ready: "ready", failed: "failed"
  }, prefix: :ingest

  # nil caption_status = never described (or no vision model configured).
  enum :caption_status, {
    queued: "queued", processing: "processing", captioned: "captioned", failed: "failed"
  }, prefix: :caption

  validate :image_must_be_attached_and_an_image, on: :create

  # The timeline needs an order the moment the row exists; ingestion
  # replaces this with the EXIF capture time when the photo has one.
  before_validation { self.taken_at ||= Time.current }

  def display_title
    title.presence || taken_at.strftime("%B %-d, %Y")
  end

  # Same bytes, same person, already in the library (D31 dedupe): matched by
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

  # Captioning needs a model the admin has *declared* image-capable — we
  # can't probe for it, and absent that the feature simply isn't there.
  def captionable_profile
    profile = user.household.model_profile
    profile if profile&.configured? && profile.vision?
  end

  def enqueue_caption!
    update!(caption_status: :queued, caption_error: nil)
    CaptionPhotoJob.perform_later(self)
  end

  def suggested_section_records
    Section.where(slug: suggested_sections).order(:parent_id, :position) - sections
  end

  private
    def image_must_be_attached_and_an_image
      return errors.add(:image, "must be attached") unless image.attached?

      unless image.blob.content_type.to_s.start_with?("image/")
        errors.add(:image, "must be an image")
      end
    end
end
