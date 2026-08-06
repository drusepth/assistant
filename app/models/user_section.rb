class UserSection < ApplicationRecord
  belongs_to :user
  belongs_to :section

  validates :section_id, uniqueness: { scope: :user_id }
end
