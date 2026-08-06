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

  # Section toggles (D4): sections are enabled unless explicitly disabled,
  # so new sections appear for existing users without backfill.
  def section_enabled?(section)
    !user_sections.exists?(section: section, enabled: false)
  end

  def enabled_sections
    Section.top_level.where.not(id: user_sections.where(enabled: false).select(:section_id))
  end
end
