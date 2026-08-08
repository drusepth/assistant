class Household < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_one :model_profile, dependent: :destroy

  # The hero's backdrop (D-household-profile): one picture of the place or
  # the people, cropped to a cover band. Deliberately not a Photo — the
  # photo library is owned by a user, and this belongs to everyone.
  has_one_attached :banner do |attachable|
    attachable.variant :cover, resize_to_limit: [ 1600, 500 ], format: :webp, saver: { quality: 80, strip: true }
  end

  # Do you own or rent? The one routing signal that changes which help is
  # relevant: renters get deposit/repair/eviction footing, owners get
  # mortgage and property-tax footing.
  HOME_STATUSES = %w[ own rent other ].freeze

  validates :name, presence: true
  validates :home_status, inclusion: { in: HOME_STATUSES }, allow_blank: true
  validate :time_zone_is_recognized

  # Everything dated in the app — "due today", all-day events, the weekly
  # scan — is computed in this zone. Blank means the instance default
  # (UTC), which is wrong for most of the planet after 4pm; setting it once
  # here fixes every surface at once.
  def zone
    (time_zone.presence && ActiveSupport::TimeZone[time_zone]) || Time.zone
  end

  # The mailing block, free text on the D34 argument: the consumer is a
  # prompt and a letterhead, not a join, and the audience is global
  # self-hosters whose address shapes don't agree.
  def address_lines = address.to_s.lines.map(&:strip).reject(&:blank?)

  def renting? = home_status == "rent"

  def home_status_label
    case home_status
    when "own"   then "We own our home"
    when "rent"  then "We rent our home"
    when "other" then "Other living arrangement"
    end
  end

  # Whole years at this address, for the hero's anniversary and for tenancy
  # math (a lease that renews on the move-in day).
  def years_at_home(on: Date.current)
    return nil unless moved_in_on && moved_in_on <= on

    anniversary_passed = ([ on.month, on.day ] <=> [ moved_in_on.month, moved_in_on.day ]) >= 0
    on.year - moved_in_on.year - (anniversary_passed ? 0 : 1)
  end

  def home_anniversary?(on: Date.current)
    moved_in_on.present? && moved_in_on.month == on.month && moved_in_on.day == on.day && years_at_home(on: on).to_i.positive?
  end

  # Anything filled in beyond the name — the household page's "you haven't
  # told me anything yet" check.
  def profile_complete? = [ address, phone, region, moved_in_on, home_status, tagline ].any?(&:present?)

  private
    # Both spellings are accepted — the friendly Rails name ("Central Time
    # (US & Canada)") the select offers, and the IANA name ("America/Chicago")
    # a self-hoster is more likely to type.
    def time_zone_is_recognized
      return if time_zone.blank? || ActiveSupport::TimeZone[time_zone]

      errors.add(:time_zone, "isn't a time zone I recognize")
    end
end
