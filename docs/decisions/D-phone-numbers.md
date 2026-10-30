<!-- decided -->
**D-phone-numbers. Phone numbers are stored as E.164, typed through one mask, and printed in one shape.**
Every phone box in the app is masked, with no opt-in:
`ApplicationFormBuilder#telephone_field` covers the model forms (contacts, the
pet's vet, the household), and `PhoneHelper#telephone_field_tag` deliberately
overrides Rails' own helper to cover forms without a model (the SMS and
Signal channels in Settings). Both take their options from one place, so
fixing the shape once fixes it everywhere. The user types only digits. The `phone-input` Stimulus controller
fills in the "(503) 555-0142" around them as they type, keeps the caret where
it was, and treats a backspace over a ")" or "-" as a backspace over the
digit before it. A browser `pattern` blocks a half-typed number before it is
submitted.

**Stored as E.164** ("+15035550142") by `PhoneNumber.normalize`, applied with
`normalizes :phone` on the model. That is the format a `tel:` link and an SMS
gateway take, and the one notification channels already require. The channels now
normalize through `PhoneNumber` too. Before this they only added a "+", so
a US number typed without its 1 was saved as a number in another country
and still passed validation. It also
turns search into a digit match: the Address Book finds "503-555" by its
digits whatever punctuation the user typed. The form doesn't decide the
stored shape; the model does, so imports, the contact picker, and a form
submitted without JavaScript all store the same thing.

**North America is the default, with "+" as the way out.** Ten bare digits
have to mean something, and this installed base mostly dials NANP numbers.
Anyone else types "+" and the country code. The mask then stops grouping,
because grouping international numbers correctly needs a per-country table,
which we don't have (and not a library, until someone needs one). Those
numbers are printed as stored.

**Nothing is guessed.** A value that isn't clearly a phone number, like
"555-1234", "020 7946 0958", or anything with an extension or words in it,
is kept exactly as written. Its edit box drops the pattern, so an old import
never blocks saving an unrelated field. An import must never turn a number
it can't read into a wrong one. Extensions are the known gap: the mask has
no place to type one yet.
