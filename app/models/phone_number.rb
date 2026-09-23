# One stored shape for every phone number the app keeps, and one printed
# shape for every place it shows one. The form's masked input
# (phone_input_controller.js, via ApplicationFormBuilder#telephone_field)
# is what the user types into; this is what the server makes of it.
#
# Stored as E.164 — "+15036149061" — because that is the form a `tel:` link,
# an SMS gateway, and a search by digits all want, and the form notification
# channels already insist on. Printed as "(503) 614-9061" for North American
# numbers; anything else is printed as stored, since grouping an
# international number correctly takes a per-country table we don't carry.
#
# North America is the default because a bare ten digits has to mean
# *something*; a number from anywhere else is typed with its "+" and
# country code, and the mask says so. A value that isn't plainly a phone
# number — "555-1234", "ext. 12", a vCard's "call the front desk" — is kept
# exactly as written rather than guessed at: an import must never turn a
# number it can't read into a wrong one.
module PhoneNumber
  # Digits and the punctuation people put between them, with at most a
  # leading "+". Anything else means the value isn't only a number, and it
  # is left alone.
  NUMBER_ONLY = /\A\+?[\d\s().\-\/]+\z/
  NANP_DISPLAY = /\A\+1(\d{3})(\d{3})(\d{4})\z/

  module_function

  # What gets saved: E.164 when the value reads unambiguously as a number,
  # the squished original when it doesn't, nil when it's blank.
  def normalize(value)
    text = value.to_s.squish
    return nil if text.empty?
    return text unless text.match?(NUMBER_ONLY)

    digits = text.delete("^0-9")
    if text.start_with?("+")
      return "+#{digits}" if digits.length.between?(8, 15)
    elsif digits.length == 10 && digits.match?(/\A[2-9]/)
      return "+1#{digits}"
    elsif digits.length == 11 && digits.match?(/\A1[2-9]/)
      return "+#{digits}"
    end

    text
  end

  # What gets shown: the North American mask for a +1 number, the stored
  # value for everything else.
  def format(value)
    return nil if value.blank?

    match = NANP_DISPLAY.match(value.to_s)
    match ? "(#{match[1]}) #{match[2]}-#{match[3]}" : value.to_s
  end
end
