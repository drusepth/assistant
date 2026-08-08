# One mirrored message (D30, EMAIL_PLAN.md §4). Deliberately NOT a
# primitive: no Visible, no Sectionable, no grants — the only read path is
# through the owning user, and content enters the primitive pool only by
# promotion (EmailMessageItem). References to primary-database rows
# (user, person, promoted items) are soft ids resolved in Ruby.
class EmailMessage < MirrorRecord
  DIRECTIONS = %w[ inbound outbound ].freeze
  SNIPPET_LENGTH = 200
  BODY_LIMIT = 20_000

  belongs_to :email_folder
  belongs_to :linked_account
  has_many :email_message_items, dependent: :delete_all

  validates :message_id, :thread_key, presence: true
  validates :direction, inclusion: { in: DIRECTIONS }

  scope :inbound, -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }
  scope :live, -> { where(backfilled: false) }
  scope :newest_first, -> { order(sent_at: :desc, id: :desc) }

  # FTS rides model callbacks, not triggers (Email::Search explains why).
  # Bodies never change after ingest, so create is the only index moment.
  after_create_commit { Email::Search.index(self) }
  after_destroy { Email::Search.remove(self) }

  def user = @user ||= User.find_by(id: user_id)

  # Soft cross-database lookup, scoped to the owner so a recycled id can
  # never surface someone else's contact.
  def person
    return nil if person_id.blank?
    @person ||= Person.find_by(id: person_id, user_id: user_id)
  end

  def thread_messages
    self.class.where(user_id: user_id, thread_key: thread_key).order(:sent_at, :id)
  end

  def replied_to?
    thread_messages.inbound.where("sent_at > ?", sent_at || created_at).exists?
  end

  def inbound? = direction == "inbound"
  def outbound? = direction == "outbound"

  # Everyone this message involves besides the mailbox owner's own address.
  def counterparty_email = inbound? ? from_email : Array(to_emails).first

  def promoted_items
    email_message_items.filter_map(&:item)
  end

  # Removal that stays removed (EMAIL_PLAN.md §3): delete the row and
  # tombstone the message_id so the next sync can't resurrect it. The
  # assistant never reads what isn't mirrored.
  def remove_from_mirror!
    transaction do
      EmailTombstone.find_or_create_by!(linked_account_id: linked_account_id, message_id: message_id)
      destroy!
    end
  end
end
