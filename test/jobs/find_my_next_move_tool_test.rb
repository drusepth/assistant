require "test_helper"

# The cross-referencing dividend (docs/CAREER.md §3.6): the counselor's
# context spans Career, Hobbies, and Education at once.
class FindMyNextMoveToolTest < ActiveJob::TestCase
  ENDPOINT = "https://api.openai.com/v1/chat/completions".freeze

  setup do
    @run = users(:one).tool_runs.create!(
      tool_slug: "find_my_next_move",
      inputs: { "itch" => "my body can't do this job at 50", "constraints" => "can't afford school" }
    )
  end

  test "the opening message draws on Career, Hobbies, and Education at once" do
    job = users(:one).notes.create!(title: "About my work", body: "Warehouse picker, 8 years.")
    job.sections << sections(:career)
    hobby = users(:one).notes.create!(title: "PC building", body: "Built 6 rigs for friends this year.")
    hobby.sections << sections(:hobbies)
    course = users(:one).goals.create!(title: "Learn basic networking", broken_down_at: Time.current)
    course.sections << sections(:education)

    stub_chat("Eight years in the warehouse and six PCs built for friends — what part of the building do you enjoy most?")

    ToolRunJob.perform_now(@run)

    assert @run.reload.done?, "done means live for a chat run"
    assert @run.tool_run_messages.sole.assistant_role?

    assert_requested(:post, ENDPOINT) do |request|
      request.body.include?("Warehouse picker") &&
        request.body.include?("Built 6 rigs") &&
        request.body.include?("Learn basic networking") &&
        request.body.include?("can't afford school")
    end
  end

  test "saving a recap lands one Career-filed note" do
    @run.tool_run_messages.create!(role: :assistant, content: "Good talk.")
    @run.update_column(:recap_requested_at, Time.current)
    stub_request(:post, ENDPOINT).to_return(
      status: 200,
      body: { choices: [ { message: { content: {
        recap: { title: "Next move — IT support", body: "Cheap test: shadow the repair shop; look up A+ cert costs." }
      }.to_json } } ] }.to_json
    )

    ChatRecapJob.perform_now(@run)

    note = @run.reload.items.grep(Note).sole
    assert_equal "Next move — IT support", note.title
    assert_equal [ sections(:career) ], note.sections.to_a
  end

  private
    def stub_chat(content)
      stub_request(:post, ENDPOINT).to_return(
        status: 200,
        body: { choices: [ { message: { content: content } } ] }.to_json
      )
    end
end
