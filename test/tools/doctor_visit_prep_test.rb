require "test_helper"

# The prep sheet's prompt (docs/HEALTH.md §8): allergies get their own block,
# worst first, because "any allergies?" is the first question in the room.
class DoctorVisitPrepTest < ActiveSupport::TestCase
  test "allergies get their own worst-first block, out of the notes dump" do
    users(:one).notes.create!(kind: Note::ALLERGY, title: "Cats", body: "sneezing", severity: "mild")
    users(:one).notes.create!(kind: Note::ALLERGY, title: "Penicillin", body: "hives", severity: "severe")

    prompt = user_prompt
    assert_match(/Allergies \(worst first\):\n- Penicillin — severe reaction — hives\n- Cats — mild reaction — sneezing/, prompt)
    assert_no_match(/Health notes:.*Penicillin/m, prompt, "listed once, not twice")
  end

  test "an untagged allergy still reaches the sheet" do
    users(:one).notes.create!(kind: Note::ALLERGY, title: "Latex", body: "rash")

    assert_match(/Allergies \(worst first\):\n- Latex — rash/, user_prompt,
      "an allergy is one whether or not the note ever got filed under Health"
    )
  end

  test "no allergies means no block at all" do
    note = users(:one).notes.create!(title: "Symptoms", body: "Headaches most mornings")
    note.sections << sections(:health)

    prompt = user_prompt
    assert_no_match(/Allergies/, prompt)
    assert_match(/Health notes:\n- Symptoms: Headaches/, prompt)
  end

  private
    def user_prompt
      run = users(:one).tool_runs.create!(tool_slug: "doctor_visit_prep", inputs: {}, status: :queued)
      Tool::DoctorVisitPrep.new(run).send(:user_prompt)
    end
end
