# A read-only public link to one recipe or one recipe book (D-share-link):
# the first sharing path in the app that leaves the household, for the
# sister in another state and the friend who asked at dinner — people who
# will never have an account here.
#
# Everything about it is deliberately narrow. The subject type is
# allowlisted (this is an unauthenticated read path and must never become a
# generic one); the token is the whole authorization, so it is long and
# unguessable; the row is the link, so revoking is deleting; and the link is
# always a thing the owner made and can see, never an ambient setting (D9).
class ShareLink < ApplicationRecord
  # Adding a type here is a decision, made once, on purpose — this is a
  # public read path and it must never become a generic one. Albums joined
  # on the same terms as recipes: a container of your own images, shared
  # whole, with the same owner guard on what travels with it.
  #
  # A Pet joined for one thing only (D-pet-vaccinations): her vaccine
  # one-sheet, for the kennel or groomer. The public page for a Pet link
  # renders that sheet and nothing else of hers — no notes, no reactions, no
  # photos beyond her avatar — and serves only the certificates attached to
  # her doses, through the token, so revoking the link cuts off the files too.
  SHAREABLE_TYPES = %w[ Recipe RecipeBook Album Pet ].freeze

  # What the create form offers, in days.
  EXPIRY_CHOICES = { "Never expires" => "", "In 7 days" => "7", "In 30 days" => "30", "In 90 days" => "90" }.freeze

  belongs_to :user
  belongs_to :subject, polymorphic: true

  has_secure_token :token, length: 24

  validates :subject_type, inclusion: { in: SHAREABLE_TYPES }
  validates :label, length: { maximum: 60 }
  validate :subject_belongs_to_the_link_owner

  scope :live, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }

  def self.expiry_from(days)
    days.present? ? days.to_i.days.from_now : nil
  end

  def expired? = expires_at.present? && expires_at.past?

  # Counted without touching updated_at: a view is not an edit, and the
  # owner's list orders by when *they* made the link.
  def record_view!
    update_columns(views_count: views_count + 1, last_viewed_at: Time.current)
  end

  private
    def subject_belongs_to_the_link_owner
      return if subject.nil?

      errors.add(:subject, "must be yours to share") if subject.user_id != user_id
    end
end
