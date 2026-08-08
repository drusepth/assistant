# A user-owned container of their own photos (D30): deliberate curation
# ("Summer 2026"), not a section lens — one photo lives in many albums.
# Albums are the normal unit of photo sharing: grant the album, and its
# photos travel with it (the album clause in Photo's read path).
class Album < ApplicationRecord
  include Visible

  has_many :album_photos, dependent: :destroy
  has_many :photos, through: :album_photos
  belongs_to :cover_photo, class_name: "Photo", optional: true

  validates :title, presence: true
  validate :cover_photo_is_own

  def cover
    cover_photo || photos.order(taken_at: :desc, id: :desc).first
  end

  private
    def cover_photo_is_own
      return if cover_photo.nil?

      errors.add(:cover_photo, "must be one of your photos") if cover_photo.user_id != user_id
    end
end
