require "test_helper"

# The never-fabricate tool (docs/CAREER.md §3.2): translation of the user's
# real record, with the honesty footer appended by code on every draft.
class TailorApplicationToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  test "lands the tailored draft and cover letter, both wearing the code-appended honesty footer" do
    Career::WinLog.log!(user: users(:one), text: "Cut picking errors 30% by reorganizing the aisle flow")
    resume = users(:one).documents.create!(title: "My resume", extracted_text: "Acme Logistics, picker, 2022–2026")
    resume.sections << sections(:career)
    run = users(:one).tool_runs.create!(
      tool_slug: "tailor_application",
      inputs: { "role" => "Shift lead at Bravo", "listing" => "Requires team leadership and inventory accuracy.",
                "resume_document_id" => resume.id.to_s }
    )
    stub_llm(
      tailored: { title: "Application draft — shift lead", body: "Bullets: reorganized aisle flow, cutting errors 30%..." },
      cover_letter: { title: "Cover letter — Bravo", body: "I've spent four years on the floor at Acme..." },
      follow_ups: [ { title: "Proofread and send", due_on: nil } ]
    )

    run_and_add_all(run)

    run.reload
    assert run.done?

    notes = run.items.grep(Note)
    assert_equal [ "Application draft — shift lead", "Cover letter — Bravo" ], notes.map(&:title)
    notes.each do |note|
      assert_includes note.body, "nothing in a draft should claim experience, titles, dates, or credentials you don't have"
    end

    assert_equal "interview_prep", run.output["next_tools"].sole["slug"]
    assert_equal "Shift lead at Bravo", run.output["next_tools"].sole.dig("inputs", "role")

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Cut picking errors 30%") &&
        request.body.include?("Acme Logistics, picker") &&
        request.body.include?("team leadership")
    end
  end

  test "no listing at all fails friendly before any model call" do
    run = users(:one).tool_runs.create!(tool_slug: "tailor_application", inputs: { "role" => "Shift lead" })

    run_and_add_all(run)

    assert run.reload.failed?
    assert_match(/Paste the listing/, run.error)
    assert_not_requested :post, ENDPOINT
  end

  private
    def stub_llm(tailored:, cover_letter:, follow_ups:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          tailored: tailored, cover_letter: cover_letter, follow_ups: follow_ups
        }.to_json } } ] }.to_json
      )
    end
end
