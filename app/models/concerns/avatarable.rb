# One uploaded photo on a record that stands for a person: a household
# member (D-user-avatars) or a contact in the address book
# (D-contact-photos). Both render through Ui::AvatarComponent, so both want
# the same attachment, the same guardrails, and the same initials fallback —
# and a self-hoster who uploads nothing still sees exactly the tinted circle
# that was there before either feature existed.
#
# One square variant is all any surface ever renders; the original is kept
# (it leaves with the user in the D14 export) but never served, so a
# phone-camera JPEG can't end up behind a 24-pixel sidebar circle.
module Avatarable
  extend ActiveSupport::Concern

  AVATAR_CONTENT_TYPES = %w[ image/png image/jpeg image/webp image/gif ].freeze
  AVATAR_MAX_BYTES = 10.megabytes

  included do
    has_one_attached :avatar do |attachable|
      attachable.variant :thumb, resize_to_fill: [ 200, 200 ], format: :webp,
        saver: { quality: 80, strip: true }
    end

    validate :avatar_must_be_a_supported_image
  end

  # What the initials circle falls back to, and what it always was before
  # avatars existed: the first letter of the first two words of the name.
  def initials
    name.to_s.split.map { |word| word.chars.first }.join[0, 2].upcase
  end

  # An attached avatar isn't necessarily a *renderable* one — a blob whose
  # bytes libvips can't open would blow up the variant call on every page
  # that draws this person, so every surface asks this first.
  def avatar_ready?
    avatar.attached? && avatar.variable?
  end

  private
    def avatar_must_be_a_supported_image
      return unless avatar.attached?

      unless AVATAR_CONTENT_TYPES.include?(avatar.blob.content_type)
        errors.add(:avatar, "needs to be a PNG, JPEG, WEBP, or GIF image")
      end

      if avatar.blob.byte_size > AVATAR_MAX_BYTES
        errors.add(:avatar, "is bigger than #{AVATAR_MAX_BYTES / 1.megabyte} MB")
      end
    end
end
