require "test_helper"

# The owned-context gatherer behind section-reading tools: visible_to is the
# single read path (D9), and the budget drops whole lines, never truncates
# mid-sentence.
class ContextTest < ActiveSupport::TestCase
  setup do
    @note = users(:one).notes.create!(title: "Symptoms", body: "Headaches most mornings this month")
    @note.sections << sections(:health)

    @event = users(:one).events.create!(title: "Cardiology follow-up", starts_at: 2.weeks.from_now)
    @event.sections << sections(:health)

    @document = users(:one).documents.create!(title: "Lipid panel", summary: "LDL high, HDL normal")
    @document.sections << sections(:health)

    @task = users(:one).tasks.create!(title: "Refill prescription", due_on: 3.days.from_now.to_date)
    @task.sections << sections(:health)
  end

  test "renders the user's items in the sections as dated bullet blocks" do
    prompt = context.to_prompt

    assert_match(/Appointments and events:\n- \d{4}-\d{2}-\d{2} — Cardiology follow-up \(upcoming\)/, prompt)
    assert_match(/Notes:\n- \d{4}-\d{2}-\d{2} — Symptoms: Headaches most mornings/, prompt)
    assert_match(/Documents:\n- Lipid panel: LDL high/, prompt)
    assert_match(/Open tasks:\n- Refill prescription \(due #{@task.due_on.iso8601}\)/, prompt)
  end

  test "another member's private items never leak in" do
    private_note = users(:two).notes.create!(body: "Bob's private symptom log")
    private_note.sections << sections(:health)

    assert_no_match(/Bob's private/, context.to_prompt)
  end

  test "a shared item is included — visible_to is the read path" do
    shared_note = users(:two).notes.create!(body: "Bob's shared allergy list")
    shared_note.sections << sections(:health)
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: shared_note)

    assert_match(/Bob's shared allergy list/, context.to_prompt)
  end

  test "items tagged elsewhere stay out of the lens" do
    career_note = users(:one).notes.create!(body: "Resume rewrite ideas")
    career_note.sections << sections(:career)

    assert_no_match(/Resume rewrite/, context.to_prompt)
  end

  test "the budget drops whole lines rather than truncating mid-line" do
    prompt = context(budget: 70).to_prompt

    assert_match(/Cardiology follow-up \(upcoming\)$/, prompt,
      "the surviving line is intact, not cut mid-sentence")
    assert_no_match(/Refill prescription/, prompt, "later blocks fall off the budget")
    assert prompt.length <= 70 + "Appointments and events:\n".length,
      "within budget plus heading overhead"
  end

  test "completed tasks and empty sections leave no trace" do
    @task.complete!
    prompt = context.to_prompt

    assert_no_match(/Open tasks/, prompt, "a block with no lines renders no heading")
  end

  test "empty when nothing is tracked" do
    assert Tool::Context.new(user: users(:one), section_slugs: %w[ hobbies ]).empty?
  end

  private
    def context(budget: Tool::Context::DEFAULT_BUDGET)
      Tool::Context.new(user: users(:one), section_slugs: %w[ health ], budget: budget)
    end
end
