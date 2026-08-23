class User < ApplicationRecord
  belongs_to :household

  has_secure_password
  has_many :sessions, dependent: :destroy

  has_many :user_sections, dependent: :destroy

  has_many :events, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :documents, dependent: :destroy
  has_many :people, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :photos, dependent: :destroy
  has_many :albums, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :recipe_books, dependent: :destroy
  has_many :share_links, dependent: :destroy
  has_many :tool_runs, dependent: :destroy
  has_many :suggestions, dependent: :destroy
  has_many :job_feeds, dependent: :destroy
  has_many :linked_accounts, dependent: :destroy
  has_many :email_sender_rules, dependent: :destroy
  has_many :notification_channels, dependent: :destroy
  has_many :care_settings, dependent: :destroy
  has_many :spending_accounts, dependent: :destroy
  has_many :budget_categories, dependent: :destroy
  has_many :spending_rules, dependent: :destroy

  has_one :keyring, dependent: :destroy
  has_many :credentials, dependent: :destroy
  has_many :credential_keys, dependent: :destroy
  has_many :emergency_contacts, dependent: :destroy
  has_many :emergency_contact_roles, class_name: "EmergencyContact", foreign_key: :contact_user_id,
    inverse_of: :contact_user, dependent: :destroy
  has_many :vault_events, dependent: :destroy

  # The takeable copy of your life (M4.2): regenerated on demand, only the
  # newest kept.
  has_one_attached :export_archive

  # Your face on every surface (D-user-avatars). One square variant is all
  # any surface ever renders — the original is kept but never served, so a
  # phone-camera JPEG doesn't get shipped to a sidebar 24 pixels wide.
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 200, 200 ], format: :webp,
      saver: { quality: 80, strip: true }
  end

  AVATAR_CONTENT_TYPES = %w[ image/png image/jpeg image/webp image/gif ].freeze
  AVATAR_MAX_BYTES = 10.megabytes

  has_many :granted_access_grants, class_name: "AccessGrant", foreign_key: :grantor_id,
    inverse_of: :grantor, dependent: :destroy
  has_many :received_access_grants, class_name: "AccessGrant", foreign_key: :grantee_id,
    inverse_of: :grantee, dependent: :destroy

  # Other users' Person records that point at this account (D8): keep the
  # contact, drop the account link, when this user is removed.
  has_many :linked_people, class_name: "Person", foreign_key: :linked_user_id,
    inverse_of: :linked_user, dependent: :nullify
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :inviter_id,
    inverse_of: :inviter, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true
  validate :avatar_must_be_a_supported_image

  # What the initials circle falls back to, and what it always was before
  # avatars existed: the first letter of the first two words of the name.
  def initials
    name.to_s.split.map { |word| word.chars.first }.join[0, 2].upcase
  end

  # An attached avatar isn't necessarily a *renderable* one — a blob whose
  # bytes libvips can't open would blow up the variant call on every page
  # that draws this user, so every surface asks this first.
  def avatar_ready?
    avatar.attached? && avatar.variable?
  end

  # Section toggles (D4): sections are enabled unless explicitly disabled,
  # so new sections appear for existing users without backfill.
  def section_enabled?(section)
    !user_sections.exists?(section: section, enabled: false)
  end

  # Top-level sections in this user's sidebar order: a dragged position on
  # user_sections wins; sections the user never reordered sort after those,
  # keeping the taxonomy default among themselves.
  def ordered_sections
    preferences = user_sections.index_by(&:section_id)
    Section.top_level.sort_by do |section|
      [ preferences[section.id]&.position || Float::INFINITY, section.position ]
    end
  end

  # The agent dial for a top-level section (D20): a disabled section is
  # implicitly off; absence of a row means the Quiet default.
  def agent_level_for(section)
    return "off" unless section_enabled?(section)

    user_sections.find_by(section: section)&.agent_level || UserSection::DEFAULT_AGENT_LEVEL
  end

  def enabled_sections
    disabled_ids = user_sections.where(enabled: false).pluck(:section_id)
    ordered_sections.reject { |section| disabled_ids.include?(section.id) }
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
