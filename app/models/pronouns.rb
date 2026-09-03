# How the app refers to someone in its own copy — a pet, a contact, a
# household member (D-pronouns).
#
# This exists because the app writes sentences *about* people and animals all
# day (a nudge, a flash, a card subtitle, a prompt sent to a model), and every
# one of those sentences needs a pronoun. Before this, they were all written
# with one hardcoded in, which is wrong about most of the people and animals
# it was written about.
#
# The set is closed and small on purpose: she, he, they. Anything unrecorded
# is "they" rather than a guess, which is also what someone who'd rather not
# say gets by leaving the field alone. A neopronoun set would be a table
# rather than a column and is not what the 99% are blocked on today; when it
# is, `SETS` is the one place it lands.
class Pronouns < Data.define(:subject, :object, :possessive, :reflexive)
  SETS = {
    "she" => %w[ she her her herself ],
    "he" => %w[ he him his himself ],
    "they" => %w[ they them their themselves ]
  }.freeze

  # Not a fourth set: "unrecorded" and "they" are the same answer, and giving
  # them separate representations would only invite copy that says "unknown".
  DEFAULT = "they"
  KEYS = SETS.keys.freeze

  # What a picker shows. The stored value is the subject pronoun, so the row
  # a household member recognises ("she/her") and the key are the same fact.
  LABELS = { "she" => "she / her", "he" => "he / him", "they" => "they / them" }.freeze

  def self.for(key) = new(*SETS.fetch(key.to_s.presence || DEFAULT, SETS.fetch(DEFAULT)))
  def self.options = KEYS.map { |key| [ LABELS[key], key ] }

  # "they" takes a plural verb, so copy built from these has to ask rather
  # than assume: `"What #{p.subject} #{p.verb("eats", "eat")}"`.
  def plural? = subject == "they"
  def verb(singular, plural) = plural? ? plural : singular

  # The contraction the copy actually reaches for, so no view has to write
  # `p.subject + (p.plural? ? "'re" : "'s")` inline.
  def is = "#{subject}#{verb("'s", "'re")}"

  # What a model is told, in the one form that leaves it no room to default:
  # "she/her/her". Every context builder that describes a person or an animal
  # sends this.
  def slashed = "#{subject}/#{object}/#{possessive}"
end
