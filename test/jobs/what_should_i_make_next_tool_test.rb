require "test_helper"

# The Tier-A content tool: evergreen ideas from the model's knowledge applied
# to the user's own hobby context, landing as an idea-menu Note.
class WhatShouldIMakeNextToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @lens = Hobbies::Lens.find_or_create!("Knitting")

    @finished = users(:one).goals.create!(title: "Knit a scarf", status: :done)
    @finished.sections = [ @lens ]
    @note = users(:one).notes.create!(title: "Stash", body: "Three skeins of worsted merino, size 8 needles")
    @note.sections = [ @lens ]
  end

  test "lands an idea menu as a note filed under the hobby" do
    run = run_for(hobby: "knitting")
    stub_ideas([
      { title: "A cabled hat", pitch: "Your first cables, one skein.", first_step: "Cast on 96 stitches in the round" },
      { title: "Colorwork mittens", pitch: "Uses two stash skeins.", first_step: "Pick a two-color chart you like" }
    ])

    ToolRunJob.perform_now(run)

    run.reload
    assert run.done?

    note = run.items.grep(Note).sole
    assert_equal "Project ideas — Knitting", note.title
    assert_includes note.body, "1. A cabled hat"
    assert_includes note.body, "First step: Cast on 96 stitches in the round"
    assert_includes note.sections, sections(:hobbies)
    assert_includes note.sections, @lens
  end

  test "the model sees the hobby's own context — finished projects and notes" do
    run = run_for(hobby: "Knitting")
    stub_ideas([ { title: "Socks" } ])

    ToolRunJob.perform_now(run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Knit a scarf (finished)") && request.body.include?("worsted merino")
    end
  end

  test "with no hobby named it draws on everything filed under Hobbies" do
    run = run_for(hobby: "")
    stub_ideas([ { title: "Something" } ])

    ToolRunJob.perform_now(run)

    assert run.reload.done?
    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("your hobbies") && request.body.include?("Knit a scarf")
    end
  end

  test "with nothing to work from it fails with guidance instead of calling the model" do
    Section.custom.destroy_all
    users(:one).goals.destroy_all
    users(:one).notes.destroy_all

    run = run_for(hobby: "")
    ToolRunJob.perform_now(run)

    run.reload
    assert run.failed?
    assert_match "Start-a-hobby", run.error
    assert_not_requested :post, ENDPOINT
  end

  test "an empty idea list fails the run" do
    run = run_for(hobby: "Knitting")
    stub_ideas([])

    ToolRunJob.perform_now(run)

    assert run.reload.failed?
    assert_empty run.items
  end

  private
    def run_for(hobby:)
      users(:one).tool_runs.create!(tool_slug: "what_should_i_make_next", inputs: { "hobby" => hobby })
    end

    def stub_ideas(ideas)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: { ideas: ideas }.to_json } } ] }.to_json
      )
    end
end
