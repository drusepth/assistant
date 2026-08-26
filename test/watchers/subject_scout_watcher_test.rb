require "test_helper"

# Suggested subjects (docs/EDUCATION_PLAN.md §7): deterministic candidates
# from the affinity map over the learner's *used* lenses, reason on the
# card, dismissals permanent; the model extension covers only unmapped
# lenses and never breaks the scan.
class SubjectScoutWatcherTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @user = users(:one)
    @lens = Hobbies::Lens.find_or_create!("Theatre")
  end

  test "a used lens with a mapped affinity earns one insight with the reason and the enrollment door" do
    tag_item_into(@lens)

    Watcher::SubjectScout.new(@user).scan

    suggestion = @user.suggestions.sole
    assert suggestion.insight?
    assert_equal "Worth studying: Public speaking & rhetoric", suggestion.title
    assert_match(/Theatre lens/, suggestion.body)
    assert_equal "learn_something", suggestion.tool_action["slug"]
    assert_equal "Public speaking & rhetoric", suggestion.tool_action["inputs"]["topic"]
    assert_empty suggestion.sections, "begin-zone and Dashboard only — never doubled into Attend"

    Watcher::SubjectScout.new(@user).scan
    assert_equal 1, @user.suggestions.count, "one per lens+subject, ever"
  end

  test "an unused lens is not this learner's signal" do
    Watcher::SubjectScout.new(@user).scan
    assert_empty @user.suggestions
  end

  test "already studying it means no card" do
    tag_item_into(@lens)
    @user.subjects.create!(title: "Public speaking & rhetoric", tree_built_at: Time.current)

    Watcher::SubjectScout.new(@user).scan
    assert_empty @user.suggestions
  end

  test "the model extension covers unmapped lenses and a model failure never breaks the scan" do
    lens = Hobbies::Lens.find_or_create!("Beekeeping")
    tag_item_into(lens)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        picks: [ { index: 0, subject: "Entomology", reason: "Your hives are an insect lab already." } ]
      }.to_json } } ] }.to_json
    )

    Watcher::SubjectScout.new(@user).scan
    assert_equal "Worth studying: Entomology", @user.suggestions.sole.title

    @user.suggestions.destroy_all
    stub_request(:post, ENDPOINT).to_return(status: 500, body: "boom")
    Watcher::SubjectScout.new(@user).scan
    assert_empty @user.suggestions, "garnish fails silently"
  end

  private
    def tag_item_into(lens)
      task = @user.tasks.create!(title: "Rehearse")
      task.sections << lens
    end
end
