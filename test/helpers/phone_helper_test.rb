require "test_helper"

class PhoneHelperTest < ActionView::TestCase
  test "a model-less phone box gets the same mask as the builder's" do
    html = telephone_field_tag(:to, "+15036149061", id: "sms_to", class: "input")

    assert_match 'type="tel"', html
    assert_match 'value="(503) 614-9061"', html
    assert_match 'data-controller="phone-input"', html
    assert_match 'id="sms_to"', html
    assert_match "pattern=", html
  end

  test "phone_link prints the mask and dials E.164" do
    html = phone_link("+15036149061")

    assert_match 'href="tel:+15036149061"', html
    assert_match ">(503) 614-9061<", html
  end

  test "phone_link still links a number kept as typed" do
    assert_match 'href="tel:555-1234"', phone_link("555-1234")
  end
end
