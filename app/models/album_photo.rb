class AlbumPhoto < ApplicationRecord
  belongs_to :album
  belongs_to :photo

  validates :photo_id, uniqueness: { scope: :album_id }
  # v1 albums hold only the owner's photos; contributions are Q15.
  validate :photo_belongs_to_album_owner

  private
    def photo_belongs_to_album_owner
      return if album.nil? || photo.nil?

      errors.add(:photo, "must belong to the album's owner") if photo.user_id != album.user_id
    end
end
