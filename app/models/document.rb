class Document < ApplicationRecord
  include Visible
  include Sectionable

  has_one_attached :file

  validates :title, presence: true
end
