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

  test "registry finds tools by section, including from the parent section" do
    assert_includes Tool.for_section(sections(:disputes)), Tool::DisputeLetter
    assert_includes Tool.for_section(sections(:rights)), Tool::DisputeLetter,
      "a tool on a subsection shows on its parent's page too"
    assert_includes Tool.for_section(sections(:health)), Tool::ResultsExplainer
    assert_includes Tool.for_section(sections(:health)), Tool::InsuranceAppeal,
      "a tool registered on two sections shows on both"
    assert_empty Tool.for_section(sections(:hobbies))
  end

  test "next_steps re-resolves stored slugs and skips retired ones" do
    run = users(:one).tool_runs.create!(tool_slug: "dispute_letter", inputs: { "document_id" => "1" })
    run.update!(output: { "next_tools" => [
      { "slug" => "insurance_appeal", "inputs" => { "document_id" => "7" }, "reason" => "why" },
      { "slug" => "tool_we_deleted_in_v2", "inputs" => {} },
      "not even a hash"
    ] })

    steps = run.next_steps
    assert_equal [ Tool::InsuranceAppeal ], steps.map(&:tool)
    assert_equal({ "document_id" => "7" }, steps.first.inputs)
    assert_equal "why", steps.first.reason
  end

  test "items returns the primitives a run created" do
    run = users(:one).tool_runs.create!(tool_slug: "dispute_letter", inputs: { "document_id" => "1" })
    note = users(:one).notes.create!(body: "Draft")
    run.tool_run_items.create!(item: note)

    assert_equal [ note ], run.items
  end
end
