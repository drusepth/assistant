# A hobby the model saw in what you read but nobody has named yet
# (D-hobby-spotting). Written by `Hobbies::Spotter` on the agent's scan,
# read by the Hobbies hub's "Add another hobby" chips — the quiet surface
# for the same signal `Watcher::HobbyFromFeeds` says out loud once.
#
# It is a *candidate*, not an action: nothing here files anything, and the
# lens is created only when the user clicks the chip or types the name. The
# write-surface discipline of D20 is untouched — this row proposes, the
# controller (running for the user) disposes.
#
# `feed_ids` is what the chip is worth: the unfiled feeds the model said
# belong to this name, so naming the hobby moves them in the same request
# instead of paying a second model call to re-derive an answer we already
# have. They are ids rather than an association because the row is a
# snapshot of one scan — a feed unfollowed in the meantime should simply
# drop out, not leave a dangling join.
#
# Rows are per-user, because feeds are (D9): a lens is household-shared,
# somebody else's reading list is not.
class SpottedHobby < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, length: { maximum: 40 },
    uniqueness: { scope: :user_id, case_sensitive: false }

  scope :ordered, -> { order(:position, :id) }

  # The feeds this candidate still stands on: active, still followed, still
  # the user's own.
  def feeds = user.feeds.active.where(id: feed_ids)
end
