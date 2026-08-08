require "test_helper"

class OnThisDayWatcherTest < ActiveSupport::TestCase
  setup { @alice = users(:one) }

  test "photos from around this date in a past year produce one look-back per year" do
    photo_taken_at(1.year.ago)
    photo_taken_at(1.year.ago + 2.days, fixture: "photo_no_exif.jpg")

    assert_difference("Suggestion.count") { Watcher::OnThisDay.new(@alice).scan }

    suggestion = @alice.suggestions.last
    assert suggestion.insight?
    assert_match "1 year ago", suggestion.title
    assert_match "2 photos", suggestion.body
    assert_equal "/photos?year=#{1.year.ago.year}", suggestion.path_action
    assert_equal "View", suggestion.accept_label
  end

  test "photos outside the window, or from this year, stay quiet" do
    photo_taken_at(1.year.ago + 30.days)
    photo_taken_at(2.days.ago, fixture: "photo_no_exif.jpg")

    assert_no_difference("Suggestion.count") { Watcher::OnThisDay.new(@alice).scan }
  end

  test "a dismissed look-back stays gone for the rest of the year" do
    photo_taken_at(1.year.ago)

    Watcher::OnThisDay.new(@alice).scan
    @alice.suggestions.last.dismiss!

    assert_no_difference("Suggestion.count") { Watcher::OnThisDay.new(@alice).scan }
  end

  test "accepting a look-back redirects into the filtered timeline" do
    photo_taken_at(1.year.ago)
    Watcher::OnThisDay.new(@alice).scan
    suggestion = @alice.suggestions.last

    session = sign_in_session(@alice)
    session.patch "/suggestions/#{suggestion.id}/accept"
    assert_equal 302, session.response.status
    assert_includes session.response.location, "/photos?year="
    assert suggestion.reload.accepted?
  end

  private
    def photo_taken_at(time, fixture: "photo.jpg")
      photo = @alice.photos.create!(image: {
        io: File.open(file_fixture(fixture)), filename: fixture, content_type: "image/jpeg"
      })
      photo.update!(taken_at: time)
      photo
    end

    def sign_in_session(user)
      ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
        session.post "/session", params: { email_address: user.email_address, password: "password" }
      end
    end
end
