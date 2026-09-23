module PhoneHelper
  # A number as the app prints it — "(503) 614-9061" — dialing the stored
  # E.164 underneath (PhoneNumber).
  def phone_link(number, **options)
    phone_to number, PhoneNumber.format(number), **options
  end
end
