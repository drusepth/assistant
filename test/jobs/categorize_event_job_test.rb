require "test_helper"

class CategorizeEventJobTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @event = users(:one).events.create!(
      title: "Dentist at 3pm", starts_at: Date.new(2026, 8, 10), all_day: true
    )
  end

  test "files the event into sections and sets the time it implies" do
    stub_llm(sections: [ "health", "not-a-real-slug" ], start_time: "15:00", end_time: "15:30")

    CategorizeEventJob.perform_now(@event)

    @event.reload
    assert_equal [ sections(:health) ], @event.sections.to_a
    assert_not @event.all_day?
    assert_equal Time.zone.local(2026, 8, 10, 15, 0), @event.starts_at
    assert_equal Time.zone.local(2026, 8, 10, 15, 30), @event.ends_at
  end

  test "stays all-day when no time is implied" do
    stub_llm(sections: [ "hobbies" ], start_time: nil, end_time: nil)

    CategorizeEventJob.perform_now(@event)

    @event.reload
    assert @event.all_day?
    assert_equal Time.zone.local(2026, 8, 10), @event.starts_at
  end

  test "never touches times the user set themselves" do
    timed = users(:one).events.create!(
      title: "Standup", starts_at: Time.zone.local(2026, 8, 10, 9, 0), all_day: false
    )
    stub_llm(sections: [ "career" ], start_time: "15:00", end_time: nil)

    CategorizeEventJob.perform_now(timed)

    timed.reload
    assert_equal Time.zone.local(2026, 8, 10, 9, 0), timed.starts_at
    assert_equal [ sections(:career) ], timed.sections.to_a
  end

  test "an invalid time from the model is ignored" do
    stub_llm(sections: [], start_time: "3pm-ish", end_time: "99:99")

    CategorizeEventJob.perform_now(@event)

    assert @event.reload.all_day?
  end

  test "sends the event, its date, and taxonomy to the model" do
    stub_llm(sections: [], start_time: nil, end_time: nil)
    CategorizeEventJob.perform_now(@event)

    assert_requested(:post, ENDPOINT) do |request|
      content = JSON.parse(request.body)["messages"].last["content"]
      content.include?("Dentist at 3pm") &&
        content.include?("2026-08-10") &&
        content.include?("renting — Rights · Renting")
    end
  end

  test "skips events the user already tagged, without calling the provider" do
    @event.sections << sections(:health)

    CategorizeEventJob.perform_now(@event)

    assert_not_requested :post, ENDPOINT
  end

  test "does nothing without a configured model profile" do
    event = users(:outsider).events.create!(title: "No AI here", starts_at: Date.current, all_day: true)

    CategorizeEventJob.perform_now(event)

    assert_not_requested :post, ENDPOINT
  end

  test "provider errors leave the event unsorted instead of raising" do
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")

    CategorizeEventJob.perform_now(@event)

    assert_empty @event.reload.sections
  end

  private
    def stub_llm(sections:, start_time:, end_time:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          sections: sections, start_time: start_time, end_time: end_time
        }.to_json } } ] }.to_json
      )
    end
end
