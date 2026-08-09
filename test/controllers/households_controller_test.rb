require "test_helper"

class HouseholdsControllerTest < ActionDispatch::IntegrationTest
  test "the household page shows the profile, members, and invites to an admin" do
    sign_in_as users(:one)
    users(:one).household.update!(name: "Smith Household", address: "123 Maple Street\nAustin, TX 78701",
      phone: "(512) 555-0142", moved_in_on: Date.new(2019, 6, 1), home_status: "rent")

    get household_path
    assert_response :success
    assert_select "h1", text: "Household"
    assert_select "form[action=?]", household_path
    assert_match "123 Maple Street", response.body
    assert_match "Invite someone", response.body
  end

  test "a member with an uploaded photo shows it; everyone else keeps their initials" do
    sign_in_as users(:one)
    users(:two).avatar.attach(io: file_fixture("photo.jpg").open, filename: "photo.jpg", content_type: "image/jpeg")

    get household_path
    assert_response :success
    assert_select "img", count: 1
    assert_match "AS", response.body # Alice Smith, who hasn't uploaded one
  end

  test "a non-admin reads the profile without the forms" do
    sign_in_as users(:two)
    users(:two).household.update!(phone: "(512) 555-0142")

    get household_path
    assert_response :success
    assert_match "(512) 555-0142", response.body
    assert_select "form[action=?]", household_path, count: 0
    assert_select "input[name=?]", "invitation[name]", count: 0
  end

  test "an admin sets the household profile, region included (D34)" do
    sign_in_as users(:one)
    patch household_path, params: { household: {
      name: "The Loud House", region: "Texas, USA", address: "123 Maple Street",
      phone: "(512) 555-0142", home_status: "rent", moved_in_on: "2019-06-01",
      time_zone: "Central Time (US & Canada)", tagline: "Chaos, catered"
    } }

    assert_redirected_to household_path
    household = users(:one).household.reload
    assert_equal "Texas, USA", household.region
    assert_equal "The Loud House", household.name
    assert_equal [ "123 Maple Street" ], household.address_lines
    assert_equal Date.new(2019, 6, 1), household.moved_in_on
    assert household.renting?
    assert_equal "America/Chicago", household.zone.tzinfo.name
  end

  test "a non-admin cannot" do
    sign_in_as users(:two)
    patch household_path, params: { household: { region: "Nope" } }

    assert_redirected_to household_path
    assert_nil users(:two).household.reload.region
  end

  test "an admin attaches and removes the dashboard banner" do
    sign_in_as users(:one)
    banner = fixture_file_upload("photo.jpg", "image/jpeg")

    patch household_path, params: { household: { banner: banner } }
    assert users(:one).household.reload.banner.attached?

    perform_enqueued_jobs do
      delete banner_household_path
    end
    assert_redirected_to household_path
    assert_not users(:one).household.reload.banner.attached?
  end

  test "a non-admin cannot remove the banner" do
    users(:one).household.banner.attach(fixture_file_upload("photo.jpg", "image/jpeg"))
    sign_in_as users(:two)

    perform_enqueued_jobs { delete banner_household_path }
    assert_redirected_to household_path
    assert users(:two).household.reload.banner.attached?
  end

  test "an unrecognized time zone is rejected rather than silently stored" do
    sign_in_as users(:one)
    patch household_path, params: { household: { time_zone: "Middle Earth" } }

    assert_response :unprocessable_entity
    assert_nil users(:one).household.reload.time_zone
  end
end
