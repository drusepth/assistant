require "test_helper"

class ToolRunTest < ActiveSupport::TestCase
  test "valid with a registered tool and its required inputs" do
    run = users(:one).tool_runs.new(tool_slug: "dispute_letter", inputs: { "document_id" => "1" })
    assert run.valid?
    assert run.queued?
  end

  test "rejects an unregistered tool slug" do
    run = users(:one).tool_runs.new(tool_slug: "rm_rf", inputs: {})
    assert_not run.valid?
  end

  test "rejects a run missing a required input" do
    run = users(:one).tool_runs.new(tool_slug: "dispute_letter", inputs: { "intent" => "fix it" })
    assert_not run.valid?
    assert_match(/needs an answer/, run.errors.full_messages.to_sentence)
  end

  test "tool resolves the definition" do
    run = users(:one).tool_runs.new(tool_slug: "dispute_letter")
    assert_equal Tool::DisputeLetter, run.tool
  end

  test "registry finds tools by section, in both directions along the taxonomy" do
    assert_includes Tool.for_section(sections(:disputes)), Tool::DisputeLetter
    assert_includes Tool.for_section(sections(:rights)), Tool::DisputeLetter,
      "a tool on a subsection shows on its parent's page too"
    assert_includes Tool.for_section(sections(:money)), Tool::CancelSubscription,
      "subscriptions tools surface on Money"
    assert_includes Tool.for_section(sections(:hobbies)), Tool::StartAHobby

    lens = Hobbies::Lens.find_or_create!("Guitar")
    assert_includes Tool.for_section(lens), Tool::FindYourPeople,
      "a tool on a parent shows on each subsection's page — hobby lenses (D21) can't be registered on ahead of time"
    assert_empty Tool.for_section(sections(:career))
  end

  test "items returns the primitives a run created" do
    run = users(:one).tool_runs.create!(tool_slug: "dispute_letter", inputs: { "document_id" => "1" })
    note = users(:one).notes.create!(body: "Draft")
    run.tool_run_items.create!(item: note)

    assert_equal [ note ], run.items
  end
end
