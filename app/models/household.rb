class Household < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_one :model_profile, dependent: :destroy

  validates :name, presence: true
end
