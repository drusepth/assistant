# Promotion provenance (EMAIL_PLAN.md §4): what a mirrored message became.
# Lives in the mirror database and dies with it; the promoted primitive
# never depends on this row. The item reference is soft polymorphic —
# resolved in Ruby, tolerant of the primitive having been deleted.
class EmailMessageItem < MirrorRecord
  ITEM_TYPES = %w[ Task Event Note Document ].freeze

  belongs_to :email_message

  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :item_id, presence: true

  def item
    return nil unless ITEM_TYPES.include?(item_type)
    item_type.constantize.find_by(id: item_id, user_id: email_message.user_id)
  end
end
