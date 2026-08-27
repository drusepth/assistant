# What a hobby means, in the user's own words, for the model that reads
# stories (D-story-matching §4).
#
# The first version of this was a list of words matched against headlines.
# That was the wrong shape twice over: a word list is a promise to keep
# enumerating a subject nobody can enumerate, and matching text is the kind
# of decision this app has an assistant for. So the words became prose, and
# the prose is *context for a classifier* rather than logic — nothing here
# is compared against anything.
#
# It gives the user the ownership the word list gave them without the
# brittleness: "Birding means local birds, identification and optics — not
# the band Warbler Records" is a sentence a person can write, argue with,
# and delete.
#
# Per user, not per section: a lens is household-shared, but this is shaped
# by one person's reading and one person's corrections (D9).
class HobbyBrief < ApplicationRecord
  belongs_to :user
  belongs_to :section

  MAX_LENGTH = 600

  validates :user_id, uniqueness: { scope: :section_id }
  validates :description, length: { maximum: MAX_LENGTH }

  scope :enabled, -> { where(enabled: true) }

  normalizes :description, with: ->(text) { text.to_s.squish.presence }

  def self.for(user, section) = find_or_initialize_by(user: user, section: section)

  # Which hobbies the router is allowed to put stories in: every hobby lens
  # the user has, minus the ones they switched off. A hobby with no brief
  # row at all is on — the feature should work the moment a hobby exists,
  # not once somebody has written it an essay.
  def self.routable_sections(user)
    lenses = Hobbies::MapFeeds.askable_lenses
    off = where(user: user, enabled: false).pluck(:section_id).to_set
    lenses.reject { |lens| off.include?(lens.id) }
  end

  def routings = StoryRouting.where(section_id: section_id,
    feed_item_id: FeedItem.where(feed_id: user.feeds.select(:id)).select(:id))
end
