require "test_helper"

class ReviewsDueWatcherTest < ActiveSupport::TestCase
  test "a small queue stays quiet; a real one nudges once a week" do
    3.times { |i| due_item("p#{i}") }
    Watcher::ReviewsDue.new(users(:one)).scan
    assert_empty users(:one).suggestions

    2.times { |i| due_item("q#{i}") }
    Watcher::ReviewsDue.new(users(:one)).scan
    suggestion = users(:one).suggestions.sole
    assert_match "5 review cards", suggestion.title
    assert_equal "/reviews", suggestion.path_action

    Watcher::ReviewsDue.new(users(:one)).scan
    assert_equal 1, users(:one).suggestions.count, "fingerprint-deduped inside the week"
  end

  private
    def due_item(prompt)
      users(:one).review_items.create!(topic: topics(:fractions_compare), prompt: prompt, due_at: 1.hour.ago)
    end
end
