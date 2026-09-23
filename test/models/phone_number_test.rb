require "test_helper"

class PhoneNumberTest < ActiveSupport::TestCase
  test "a ten-digit number in any punctuation is stored as E.164" do
    [ "503-614-9061", "(503) 614-9061", "503.614.9061", "5036149061", " 503 614 9061 " ].each do |typed|
      assert_equal "+15036149061", PhoneNumber.normalize(typed), typed
    end
  end

  test "a leading 1 is the country code" do
    assert_equal "+15036149061", PhoneNumber.normalize("1 (503) 614-9061")
    assert_equal "+15036149061", PhoneNumber.normalize("+1 (503) 614-9061")
  end

  test "an international number keeps its country code" do
    assert_equal "+442079460958", PhoneNumber.normalize("+44 20 7946 0958")
  end

  test "anything it can't read unambiguously is kept as written" do
    assert_equal "555-1234", PhoneNumber.normalize("555-1234")
    assert_equal "503-614-9061 ext. 12", PhoneNumber.normalize("503-614-9061  ext. 12")
    assert_equal "020 7946 0958", PhoneNumber.normalize("020 7946 0958")
    assert_equal "+12", PhoneNumber.normalize("+12")
  end

  test "blank is nil" do
    assert_nil PhoneNumber.normalize("  ")
    assert_nil PhoneNumber.normalize(nil)
  end

  test "a North American number prints with the mask, anything else as stored" do
    assert_equal "(503) 614-9061", PhoneNumber.format("+15036149061")
    assert_equal "+442079460958", PhoneNumber.format("+442079460958")
    assert_equal "555-1234", PhoneNumber.format("555-1234")
    assert_nil PhoneNumber.format("")
  end

  test "people and households store the normalized number" do
    assert_equal "+15036149061", Person.new(phone: "503-614-9061").phone
    assert_equal "+15036149061", Household.new(phone: "(503) 614-9061").phone
  end
end
