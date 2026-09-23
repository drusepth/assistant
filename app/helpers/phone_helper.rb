module PhoneHelper
  # A number as the app prints it — "(503) 614-9061" — dialing the stored
  # E.164 underneath (PhoneNumber). Built by hand for a stored "+" number
  # because Rails' phone_to percent-encodes the "+" to "%2B", which not
  # every dialer decodes; a number kept as typed goes through phone_to.
  def phone_link(number, **options)
    label = PhoneNumber.format(number)
    return phone_to(number, label, **options) unless number.to_s.match?(/\A\+\d+\z/)

    link_to label, "tel:#{number}", **options
  end

  # The tag form of ApplicationFormBuilder#telephone_field, so a form
  # without a model (the notification channels in Settings) gets the same
  # mask. Overrides Rails' own on purpose: there is no unmasked phone box.
  def telephone_field_tag(name, value = nil, options = {})
    options = ApplicationFormBuilder.phone_input_options(value, options)
    super(name, options.delete(:value), options)
  end
  alias_method :phone_field_tag, :telephone_field_tag
end
