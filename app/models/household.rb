class Household < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_one :model_profile, dependent: :destroy

  validates :name, presence: true
  # The household clock (email plan E0): anything scheduled "at 8am" means
  # 8am here. Region is the optional Q12 jurisdiction hint ("California, US").
  # Both Rails zone names and IANA identifiers resolve.
  validate { errors.add(:time_zone, "is not a known time zone") unless ActiveSupport::TimeZone[time_zone.to_s] }

  def tz = ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone["UTC"]
end
