require "test_helper"

# D-standing-reminders: plain words into the form. The model reads the
# sentence; the form comes back prefilled; nothing is saved until the
# user's own click — and without a model the feature is off and says so.
class ReminderParseTest < ActionDispatch::IntegrationTest
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @user.household.update!(time_zone: "America/Chicago")
    sign_in_as @user
  end

  test "fills the form from a sentence and saves nothing" do
    thursday = Date.current + ((4 - Date.current.wday) % 7)
    stub_llm(body: "take the trash out", date: thursday.iso8601, time: "20:00", repeat: "weekly", days: [ "TH" ], until: nil)

    assert_no_difference -> { Reminder.count } do
      post parse_reminders_path, params: { text: "take the trash out every Thursday night" }, as: :turbo_stream
    end

    assert_response :success
    assert_select "turbo-stream[action=replace][target=new_reminder]" do
      assert_select "input[name='reminder[body]'][value='take the trash out']"
      assert_select "input[name='reminder[deliver_on]'][value=?]", thursday.iso8601
      assert_select "input[name='reminder[deliver_time]'][value='20:00']"
      assert_select "option[selected][value=weekly]"
      assert_select "input[name='reminder[repeat_days][]'][value=TH][checked]"
      assert_select "form[action=?]", reminders_path
    end
    assert_select "turbo-stream[action=replace][target=reminder_capture]", /Filled in below/
  end

  test "an answer outside the closed sets is dropped, not trusted" do
    stub_llm(body: "", date: "next thursday", time: "8pm", repeat: "fortnightly", days: [ "THU", "XX", "mo" ], until: "never")

    post parse_reminders_path, params: { text: "trash, every other week" }, as: :turbo_stream

    assert_select "turbo-stream[target=new_reminder]" do
      assert_select "input[name='reminder[body]'][value='trash, every other week']", true, "the user's own words when the model gives none"
      assert_select "input[name='reminder[deliver_on]'][value=?]", Date.current.iso8601
      assert_select "input[name='reminder[deliver_time]'][value]", false
      assert_select "option[selected][value=none]"
      assert_select "input[name='reminder[repeat_days][]'][value=MO][checked]", true, "a lowercase code still counts"
      assert_select "input[name='reminder[repeat_days][]'][checked]", 1
    end
  end

  test "a model that can't answer leaves the form alone and says so" do
    stub_request(:post, ENDPOINT).to_return(status: 401, body: { error: { message: "Incorrect API key" } }.to_json)

    post parse_reminders_path, params: { text: "trash on thursdays" }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[target=new_reminder]", false
    assert_select "turbo-stream[target=reminder_capture]" do
      assert_select "p.field-error", /Couldn't make that out/
      assert_select "input[name=text][value='trash on thursdays']", true, "what they typed is kept"
    end
  end

  test "without a model the box is gone and the page says why" do
    @user.household.model_profile.destroy!

    get today_path
    assert_select "form[action=?]", parse_reminders_path, false
    assert_select "#reminder_capture", /Set up a model/

    # A direct post with no model gets the same answer the page gives.
    post parse_reminders_path, params: { text: "trash on thursdays" }, as: :turbo_stream
    assert_select "turbo-stream[target=new_reminder]", false
    assert_select "turbo-stream[target=reminder_capture]", /Set up a model/
  end

  test "Today offers the box when a model is configured" do
    get today_path
    assert_select "form[action=?] input[name=text]", parse_reminders_path
  end

  private
    def stub_llm(**fields)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: fields.to_json } } ] }.to_json
      )
    end
end
