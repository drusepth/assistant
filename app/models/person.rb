# A contact and what matters about them. Distinct from User (a login):
# a household member usually exists as both, connected via linked_user (D8).
class Person < ApplicationRecord
  include Visible
  include Sectionable

  belongs_to :linked_user, class_name: "User", optional: true

  validates :name, presence: true
end
