class Note < ApplicationRecord
  include Visible
  include Sectionable

  validates :body, presence: true
end
