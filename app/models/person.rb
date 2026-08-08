# A contact and what matters about them. Distinct from User (a login):
# a household member usually exists as both, connected via linked_user (D8).
class Person < ApplicationRecord
  include Visible
  include Sectionable
  include AutoSortable

  AUTO_SORT_JOB = CategorizePersonJob

  belongs_to :linked_user, class_name: "User", optional: true

  has_many :photo_people, dependent: :destroy
  has_many :photos, through: :photo_people

  validates :name, presence: true
end
