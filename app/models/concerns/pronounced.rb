# Anything the app writes sentences about (D-pronouns). One `pronoun` column
# holding a subject pronoun, and a `pronouns` reader returning the set the
# copy interpolates.
#
# Blank is the normal state, not an unfinished record: it reads as "they",
# and a model that can do better — a pet, whose sex is already on file —
# overrides `pronoun_key` to say so.
module Pronounced
  extend ActiveSupport::Concern

  included do
    validates :pronoun, inclusion: { in: Pronouns::KEYS }, allow_blank: true
  end

  def pronouns = Pronouns.for(pronoun_key)

  private
    def pronoun_key = pronoun
end
