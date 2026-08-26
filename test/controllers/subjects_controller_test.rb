require "test_helper"

class SubjectsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "the education hub renders the panel with subjects and the doors" do
    get section_path("education")
    assert_response :success
    assert_match "Your subjects", response.body
    assert_match "Everyday math", response.body
    assert_match "The school shelf", response.body
    assert_match "Learn anything", response.body
  end

  test "the shelf lists every course and marks enrollment" do
    get curriculum_shelf_path
    assert_response :success
    assert_match "Civics &amp; how power works", response.body
    assert_match "Enrolled", response.body, "everyday-math is already enrolled in fixtures"
  end

  test "enrolling from the shelf instantiates the tree and tags Education" do
    assert_difference "Current.user.subjects.count" do
      post subjects_path, params: { commons_key: "financial-literacy" }
    end
    subject = Subject.order(:id).last
    assert_redirected_to subject
    assert subject.topics.any?
    assert_includes subject.sections.map(&:slug), "education"
  end

  test "a custom subject queues tree generation when a model is configured" do
    assert_enqueued_with(job: GenerateSubjectTreeJob) do
      post subjects_path, params: { subject: { title: "Bird identification", interest_frame: "walks with the kids" } }
    end
    assert_includes Subject.order(:id).last.sections.map(&:slug), "education"
  end

  test "no generation job without a model profile — the subject still lands" do
    sign_in_as users(:outsider)
    assert_no_enqueued_jobs(only: GenerateSubjectTreeJob) do
      post subjects_path, params: { subject: { title: "Bird identification" } }
    end
    assert_equal "Bird identification", users(:outsider).subjects.order(:id).last.title
  end

  test "the syllabus renders strands, topics, and states" do
    get subject_path(subjects(:algebra))
    assert_response :success
    assert_match "Fractions, decimals &amp; percentages", response.body
    assert_match "Comparing unlike denominators", response.body
    assert_match "practicing", response.body
  end

  test "a shared subject is readable but carries no verbs; a private one 404s" do
    get subject_path(subjects(:bob_civics))
    assert_response :not_found

    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: subjects(:bob_civics))
    get subject_path(subjects(:bob_civics))
    assert_response :success
    assert_match "shared by", response.body
    assert_no_match "Quiz me", response.body
  end

  test "the household card exists only where grants made it exist (D9)" do
    get section_path("education")
    assert_no_match "Household learning", response.body

    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: subjects(:bob_civics))
    get section_path("education")
    assert_match "Household learning", response.body
    assert_match "Bob Smith", response.body
    assert_match "Civics", response.body
  end

  test "the record drawer carries the year's numbers and the three generators" do
    users(:one).study_logs.create!(subject: subjects(:algebra), on: Date.current, minutes: 120, activity: :tutor)
    get section_path("education")
    assert_match "The record", response.body
    assert_match "2 hours logged this year", response.body
    assert_match new_tool_run_path("progress_report", inputs: { artifact: "Transcript" }), response.body
  end

  test "lifecycle verbs are owner-only" do
    patch pause_subject_path(subjects(:bob_civics))
    assert_response :not_found

    patch pause_subject_path(subjects(:algebra))
    assert subjects(:algebra).reload.paused?
    patch resume_subject_path(subjects(:algebra))
    assert subjects(:algebra).reload.active?
  end
end
