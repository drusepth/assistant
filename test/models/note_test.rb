require "test_helper"

class NoteTest < ActiveSupport::TestCase
  test "severity is optional but has to be one the app knows" do
    note = users(:one).notes.new(kind: Note::ALLERGY, title: "Latex", body: "rash")
    assert note.valid?, "an allergy nobody has rated is still an allergy"

    note.severity = "catastrophic"
    assert_not note.valid?
    assert_includes note.errors[:severity], "is not included in the list"
  end

  test "allergies sort worst first, and an unrated one sorts last" do
    unrated = users(:one).notes.create!(kind: Note::ALLERGY, title: "Aspirin", body: "not sure")
    mild = users(:one).notes.create!(kind: Note::ALLERGY, title: "Cats", body: "sneezing", severity: "mild")
    severe = users(:one).notes.create!(kind: Note::ALLERGY, title: "Penicillin", body: "hives", severity: "severe")
    moderate = users(:one).notes.create!(kind: Note::ALLERGY, title: "Bee stings", body: "swelling", severity: "moderate")

    assert_equal [ severe, moderate, mild, unrated ], users(:one).notes.allergies.by_severity.to_a
  end

  test "equal severities fall back to alphabetical" do
    zinc = users(:one).notes.create!(kind: Note::ALLERGY, title: "Zinc", body: "rash", severity: "mild")
    cats = users(:one).notes.create!(kind: Note::ALLERGY, title: "Cats", body: "sneezing", severity: "mild")

    assert_equal [ cats, zinc ], users(:one).notes.allergies.by_severity.to_a
  end

  test "except_allergies keeps the plain notes, whose kind is NULL" do
    plain = users(:one).notes.create!(title: "Groceries", body: "milk")
    med = users(:one).notes.create!(kind: Note::MEDICATION, title: "Lisinopril", body: "one daily")
    users(:one).notes.create!(kind: Note::ALLERGY, title: "Latex", body: "rash")

    assert_equal [ plain, med ].sort_by(&:id), users(:one).notes.except_allergies.order(:id).to_a,
      "`kind != 'allergy'` alone is NULL for a plain note, so it would drop every one"
  end

  test "the two structured kinds keep to their own scopes" do
    allergy = users(:one).notes.create!(kind: Note::ALLERGY, title: "Latex", body: "rash")
    med = users(:one).notes.create!(kind: Note::MEDICATION, title: "Lisinopril", body: "one daily")
    plain = users(:one).notes.create!(title: "Groceries", body: "milk")

    assert_equal [ allergy ], users(:one).notes.allergies.to_a
    assert_equal [ med ], users(:one).notes.medications.to_a
    assert allergy.allergy?
    assert_not med.allergy?
    assert_not plain.allergy?
  end
end
