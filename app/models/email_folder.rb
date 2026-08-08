# Sync bookkeeping for one tracked IMAP folder on one linked mailbox
# (EMAIL_PLAN.md §4). `backfilled_at` is nil while the initial window is
# still loading — the flag that separates backfill (browse-only history,
# never triaged or alerted on) from live sync.
class EmailFolder < MirrorRecord
  ROLES = %w[ inbox sent other ].freeze

  belongs_to :linked_account
  has_many :email_messages, dependent: :delete_all

  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  scope :inbox, -> { where(role: "inbox") }
  scope :sent, -> { where(role: "sent") }

  def backfilled? = backfilled_at.present?
end
