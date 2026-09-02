class Pet
  # What the app calls a pet (D-pet-pronouns). Every sentence the app writes
  # about a pet needs a pronoun, and until this existed every one of them said
  # "her" — which is wrong about half the pets in the world, and wrong about
  # every pet whose sex nobody wrote down.
  #
  # Derived from `sex` rather than asked for separately: a form that asks a
  # household for a cat's sex and then, in the next box, for the cat's
  # pronouns is a form written for a power user, and the target user is not
  # one. Unknown sex is a real answer rather than a gap — it yields "they",
  # which is also what a household who'd rather not say gets by leaving the
  # box alone.
  #
  # A subclass rather than `Data.define do … end`: a constant assigned inside
  # that block binds to the lexically enclosing scope, so SETS and UNKNOWN
  # would land on `Pet` itself, beside SPECIES, where `Pet::UNKNOWN` reads as
  # an unknown pet.
  class Pronouns < Data.define(:subject, :object, :possessive, :reflexive)
    SETS = {
      "female" => %w[ she her her herself ],
      "male" => %w[ he him his himself ]
    }.freeze
    UNKNOWN = %w[ they them their themselves ].freeze

    def self.for(sex) = new(*(SETS[sex] || UNKNOWN))

    # "they" takes a plural verb, so copy built from these has to ask rather
    # than assume: `"What #{p.subject} #{p.verb("eats", "eat")}"`.
    def plural? = subject == "they"
    def verb(singular, plural) = plural? ? plural : singular

    # The contractions the copy actually reaches for, so no view has to write
    # `p.subject + (p.plural? ? "'re" : "'s")` inline.
    def is = "#{subject}#{verb("'s", "'re")}"
  end
end
