require "test_helper"

# The radar's two sentences (D-event-radar §5.1): drafted on request from
# what the user follows and reads, and never over a sentence they wrote.
class Radar::BriefsTest < ActiveJob::TestCase
  LLM = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    birding = Hobbies::Lens.find_or_create!("Birding")
    HobbyBrief.create!(user: @user, section: birding, description: "Local birds and optics.")
    @user.feeds.create!(url: "https://example.com/feed.xml", sections: [ birding ])
      .feed_items.create!(guid: "1", title: "Where to see cranes this fall", read_at: Time.current)
  end

  test "drafts the interest brief from the hobbies and what was read, and only into a blank" do
    stub_request(:post, LLM).with { |request| @sent = request.body }
      .to_return(body: { choices: [ { message: { content: { description: "Birds, walks, free outdoor things." }.to_json } } ] }.to_json)

    assert Radar::Briefs.call(@user, "radar")
    assert_equal "Birds, walks, free outdoor things.", @user.reload.radar_brief
    prompt = JSON.parse(@sent)["messages"].map { |m| m["content"] }.join
    assert_match "Local birds and optics", prompt
    assert_match "Where to see cranes", prompt

    @user.update!(radar_brief: "Mine, thanks.")
    assert_not Radar::Briefs.call(@user, "radar")
    assert_equal "Mine, thanks.", @user.reload.radar_brief
  end

  test "the causes brief is its own question, and an empty answer leaves it blank" do
    stub_request(:post, LLM).with { |request| @sent = request.body }
      .to_return(body: { choices: [ { message: { content: { description: "" }.to_json } } ] }.to_json)

    assert_not Radar::Briefs.call(@user, "causes")
    assert_nil @user.reload.causes_brief
    assert_match "which causes", JSON.parse(@sent)["messages"].first["content"]
  end

  test "with no model nothing is enqueued, and an unknown kind is refused" do
    assert_not Radar::Briefs.enqueue(@user, "moods")
    @user.household.model_profile.update!(api_key: "")
    assert_not Radar::Briefs.enqueue(@user, "radar")
    assert_no_enqueued_jobs
  end
end
