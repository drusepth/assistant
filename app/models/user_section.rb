class UserSection < ApplicationRecord
  # The D20 agent dials, per top-level section: Off = no watchers run;
  # Quiet = weekly scan, in-app only; Active = daily scan (Today-page and
  # notification surfacing arrive later).
  AGENT_LEVELS = %w[ off quiet active ].freeze
  DEFAULT_AGENT_LEVEL = "quiet".freeze

  belongs_to :user
  belongs_to :section

  validates :section_id, uniqueness: { scope: :user_id }
  validates :agent_level, inclusion: { in: AGENT_LEVELS }
end
