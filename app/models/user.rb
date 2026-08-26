class User < ApplicationRecord
  include Avatarable

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
  has_many :trips, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :recipe_books, dependent: :destroy
  has_many :subjects, dependent: :destroy
  has_many :study_logs, dependent: :destroy
  has_many :review_items, dependent: :destroy
  has_many :share_links, dependent: :destroy
  has_many :tool_runs, dependent: :destroy
  has_many :suggestions, dependent: :destroy
  has_many :job_feeds, dependent: :destroy
  has_many :feeds, dependent: :destroy
  has_many :feed_items, through: :feeds
  has_many :linked_accounts, dependent: :destroy
  has_many :email_sender_rules, dependent: :destroy
  has_many :notification_channels, dependent: :destroy
  has_many :reminders, dependent: :destroy
  has_many :care_settings, dependent: :destroy
  has_many :spending_accounts, dependent: :destroy
  has_many :budget_categories, dependent: :destroy
  has_many :spending_rules, dependent: :destroy

  has_one :keyring, dependent: :destroy
  has_many :credentials, dependent: :destroy
  has_many :credential_keys, dependent: :destroy
  has_one :diary_setting, dependent: :destroy
  has_many :diary_entries, dependent: :destroy
  has_many :diary_entry_keys, dependent: :destroy
  has_many :diary_imports, dependent: :destroy
  has_many :emergency_contacts, dependent: :destroy
  has_many :emergency_contact_roles, class_name: "EmergencyContact", foreign_key: :contact_user_id,
    inverse_of: :contact_user, dependent: :destroy
  has_many :vault_events, dependent: :destroy

  # The takeable copy of your life (M4.2): regenerated on demand, only the
  # newest kept.
  has_one_attached :export_archive

  # Your face on every surface (D-user-avatars) — the attachment, its square
  # variant and its guardrails live in Avatarable, shared with Person.

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
  normalizes :job_title, :employer, with: ->(value) { value.strip.presence }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true

  # The work profile (D-work-profile): two plain fields the user states once
  # in Settings instead of retyping into every Career tool. Never inferred —
  # the Q8 discipline — and private to this user, not shown to the household.
  # "Cashier at Costco", "Cashier", or "at Costco"; nil when neither is set.
  def work_summary
    [ job_title, employer&.then { |name| "at #{name}" } ].compact.join(" ").presence
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
end
