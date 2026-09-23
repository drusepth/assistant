require "test_helper"

# The dollars-on-the-table tool: the program groups and the verify-footer
# (with the screening date) are assembled by code, and one application Task
# lands per likely program.
class BenefitsScreenerToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "benefits_screener",
      inputs: {
        "state" => "Ohio",
        "household_size" => "3",
        "monthly_income" => "about $2,400",
        "circumstances" => [ "Children under 18", "Recently lost a job" ]
      }
    )
  end

  test "lands the screening report grouped by likelihood, with application tasks for likely programs" do
    stub_llm(
      report: { title: "Your benefits screen", body: "With a recent job loss and two kids, the biggest opportunities are below." },
      programs: [
        { name: "Unemployment insurance", likelihood: "likely", why: "Recent job loss.", first_step: "File with Ohio Job and Family Services." },
        { name: "SNAP", likelihood: "likely", why: "Income likely within range for a household of 3.", first_step: "Apply through the Ohio benefits portal." },
        { name: "LIHEAP", likelihood: "maybe", why: "Depends on utility costs.", first_step: "Check the state energy assistance office." }
      ]
    )

    run_and_add_all(@run)

    @run.reload
    assert @run.done?

    note = @run.items.grep(Note).sole
    assert_equal "Your benefits screen", note.title
    assert_match(/Likely — worth applying:\n- Unemployment insurance — Recent job loss\. First step: File with Ohio/, note.body)
    assert_match(/Worth checking:\n- LIHEAP/, note.body)
    assert_match(/verify each program at its official site/, note.body)
    assert_match(/Screened #{Date.current.strftime("%B %-d, %Y")}/, note.body)
    assert_equal [ sections(:benefits) ], note.sections

    tasks = @run.items.grep(Task)
    assert_equal [ "Start the Unemployment insurance application", "Start the SNAP application" ], tasks.map(&:title)
    assert_equal "File with Ohio Job and Family Services.", tasks.first.notes
  end

  test "the prompt carries the structured answers including checked circumstances" do
    stub_llm(report: { title: "t", body: "b" }, programs: [])

    run_and_add_all(@run)

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Ohio") &&
        request.body.include?("Children under 18; Recently lost a job") &&
        request.body.include?("about $2,400")
    end
  end

  test "no programs still lands an honest report with the footer" do
    stub_llm(report: { title: nil, body: "This screener knows US programs best." }, programs: [])

    run_and_add_all(@run)

    @run.reload
    assert @run.done?
    note = @run.items.grep(Note).sole
    assert_match(/Benefits screen — #{Date.current.strftime("%B %Y")}/, note.title)
    assert_no_match(/Likely — worth applying/, note.body)
    assert_match(/verify each program/, note.body)
    assert_empty @run.items.grep(Task)
  end

  private
    def stub_llm(report:, programs:)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: {
          report: report, programs: programs
        }.to_json } } ] }.to_json
      )
    end
end
