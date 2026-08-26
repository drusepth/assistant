require "test_helper"

# The personalization pass (D-curriculum-commons): summaries reframed
# through the learner's world; structure and ids untouched; ids the model
# invents ignored.
class PersonalizeTreeTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "rewrites summaries by id and ignores everything else" do
    subject = subjects(:physics)
    subject.update!(interest_frame: "12-year-old skater")
    target = topics(:momentum)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        topics: [
          { id: target.id, summary: "Explain why popping harder sends the board further, with p = mv." },
          { id: 999_999, summary: "invented id" }
        ]
      }.to_json } } ] }.to_json
    )

    Education::PersonalizeTree.new(subject: subject, profile: users(:one).household.model_profile).apply!

    assert_match(/popping harder/, target.reload.summary)
    assert_equal "Friction & grip", topics(:friction).reload.title, "structure untouched"
  end
end
