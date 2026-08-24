require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:one)
    @task = users(:one).tasks.create!(title: "Mine")
  end

  test "index shows own and shared tasks only" do
    shared = users(:two).tasks.create!(title: "Shared from Bob")
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: shared)
    users(:two).tasks.create!(title: "Bob private")

    get tasks_path
    assert_response :success
    assert_match "Mine", response.body
    assert_match "Shared from Bob", response.body
    assert_no_match "Bob private", response.body
  end

  test "index renders the board with tasks in the right columns" do
    users(:one).tasks.create!(title: "Overdue thing", due_on: Date.yesterday)
    users(:one).tasks.create!(title: "Someday thing")
    users(:one).tasks.create!(title: "Finished thing", completed_at: Time.current)

    get tasks_path
    assert_response :success
    %w[Later Today Done].each { |column| assert_match column, response.body }
    assert_match "Overdue thing", response.body
    assert_match "Finished thing", response.body
    assert_match "What do you want to accomplish?", response.body
  end

  test "index shows active goals with their progress" do
    goal = users(:one).goals.create!(title: "Find a new job", broken_down_at: Time.current)
    users(:one).tasks.create!(title: "Update resume", goal: goal)

    get tasks_path
    assert_match "Find a new job", response.body
    assert_match "0 of 1 steps done", response.body
  end

  test "moves a task across the board" do
    patch move_task_path(@task, column: "today")
    assert @task.reload.today?

    patch move_task_path(@task, column: "done")
    assert @task.reload.completed?

    patch move_task_path(@task, column: "today")
    @task.reload
    assert_not @task.completed?
    assert @task.today?
  end

  test "moving a due task back to later reschedules it to tomorrow" do
    @task.update!(due_on: Date.current, bucket: :today)

    patch move_task_path(@task, column: "later")

    @task.reload
    assert @task.later?
    assert_equal Date.tomorrow, @task.due_on
  end

  test "rejects an unknown column and other users' tasks" do
    patch move_task_path(@task, column: "bogus")
    assert_response :bad_request

    other = users(:two).tasks.create!(title: "Bob's errand")
    patch move_task_path(other, column: "today")
    assert_response :not_found
  end

  test "creates a task with section tags" do
    assert_difference("Task.count") do
      post tasks_path, params: { task: { title: "Budget review", section_ids: [ sections(:money).id ] } }
    end
    assert_equal [ sections(:money) ], Task.last.sections.to_a
  end

  test "new and edit forms render, with shortcut chips on the edit date field" do
    get new_task_path
    assert_response :success

    get edit_task_path(@task)
    assert_response :success
    assert_match "Tomorrow", response.body
  end

  test "new pre-tags sections passed from a section page's quick capture" do
    get new_task_path(section_ids: [ sections(:health).id ])

    assert_response :success
    assert_match %(name="task[section_ids][]"), response.body
    assert_match "Will be filed under Health", response.body
  end

  test "quick-adding a bare title queues auto-sorting" do
    assert_enqueued_with(job: CategorizeTaskJob) do
      post tasks_path, params: { task: { title: "Renew passport by Friday" } }
    end
  end

  test "hand-tagged tasks are not auto-sorted" do
    assert_no_enqueued_jobs(only: CategorizeTaskJob) do
      post tasks_path, params: { task: { title: "Budget review", section_ids: [ sections(:money).id ] } }
    end
  end

  test "no auto-sorting without a configured model profile" do
    sign_in_as users(:outsider)
    assert_no_enqueued_jobs(only: CategorizeTaskJob) do
      post tasks_path, params: { task: { title: "Renew passport" } }
    end
  end

  test "show opens the conversation with the stored questions and no model call" do
    @task.update!(guiding_questions: [ "What skills do you enjoy using most?" ])

    get task_path(@task)
    assert_response :success
    assert_match "What skills do you enjoy using most?", response.body
    assert_match "Talk it through", response.body
    assert_no_enqueued_jobs
  end

  test "a shared task shows its answer but never the owner's conversation" do
    shared = users(:two).tasks.create!(title: "Shared", resolution: "The saved answer")
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: shared)

    get task_path(shared)
    assert_response :success
    assert_match "The saved answer", response.body
    assert_no_match "Talk it through", response.body
  end

  test "saves an answer on the task" do
    patch task_path(@task), params: { task: { resolution: "Tutoring for adult learners" } }

    assert_redirected_to @task
    assert_equal "Tutoring for adult learners", @task.reload.resolution
    assert_not @task.completed?
  end

  test "save & complete writes the answer and finishes the task in one click" do
    patch task_path(@task), params: {
      task: { resolution: "Tutoring for adult learners" }, save_and_complete: "1"
    }

    @task.reload
    assert_equal "Tutoring for adult learners", @task.resolution
    assert @task.completed?
  end

  test "completes and reopens own task" do
    patch complete_task_path(@task)
    assert @task.reload.completed?
    patch reopen_task_path(@task)
    assert_not @task.reload.completed?
  end

  test "finishing a task leaves a celebration in the flash, and reopening one doesn't" do
    patch complete_task_path(@task)
    party = JSON.parse(flash[:celebrate])
    assert_equal "board", party["tier"]  # it was the only thing left
    assert party["token"].present?
    follow_redirect!

    patch reopen_task_path(@task)
    assert_nil flash[:celebrate]
  end

  test "the board and the answer card celebrate too" do
    patch move_task_path(@task, column: "done")
    assert flash[:celebrate].present?

    other = users(:one).tasks.create!(title: "Another")
    patch task_path(other), params: { task: { resolution: "Answered" }, save_and_complete: "1" }
    assert flash[:celebrate].present?
  end

  test "no celebration for a user who turned them off" do
    users(:one).update!(celebrations: false)

    patch complete_task_path(@task)

    assert @task.reload.completed?
    assert_nil flash[:celebrate]
  end

  test "the celebration renders the party rig and never a flash banner" do
    patch complete_task_path(@task)
    follow_redirect!

    assert_response :success
    assert_select "[data-controller='celebration'][data-celebration-token-value]"
    # The payload rides the flash, but it is data, not a sentence: it must
    # never turn up as a banner full of JSON.
    assert_no_match(/\{&quot;tier&quot;|\{"tier"/, response.body)
  end

  test "reschedules own task to today or tomorrow" do
    @task.update!(due_on: 3.days.ago)

    patch reschedule_task_path(@task, to: "today")
    assert_equal Date.current, @task.reload.due_on

    patch reschedule_task_path(@task, to: "tomorrow")
    assert_equal Date.tomorrow, @task.reload.due_on
  end

  test "rescheduling says where the task went and offers the way back" do
    @task.update!(due_on: 3.days.ago)
    was = @task.due_on

    patch reschedule_task_path(@task, to: "tomorrow")
    assert_match "moved to tomorrow", flash[:notice]
    assert_match @task.title, flash[:notice]

    # The undo is just a reschedule to where the task was.
    patch flash[:undo]["url"]
    assert_equal was, @task.reload.due_on
    assert_match "moved to #{was.strftime("%b %-d")}", flash[:notice]
  end

  test "the undo reaches the page as a button in the notice" do
    @task.update!(due_on: 3.days.ago)

    patch reschedule_task_path(@task, to: "today"), headers: { "HTTP_REFERER" => today_url }
    follow_redirect!
    assert_select "[role=status]", /moved to today/
    assert_select "[role=status] form[action=?]", reschedule_task_path(@task, to: 3.days.ago.to_date.to_fs(:iso8601))
  end

  test "board cards are named, and a card keeps its name when it changes column" do
    get tasks_path
    ids = css_select("[id]").map { |el| el["id"] }
    assert_empty ids.tally.select { |_id, count| count > 1 }.keys, "ids used more than once"
    assert_select "##{dom_id(@task)}"

    # No per-column prefix: moving a card is the same card, so morph should
    # carry the node across rather than build a new one.
    patch move_task_path(@task, column: "later")
    get tasks_path
    assert_select "##{dom_id(@task)}"
  end

  test "undo puts a task that had no date back to having none" do
    undated = Current.user.tasks.create!(title: "Someday")

    patch reschedule_task_path(undated, to: "today")
    assert_equal Date.current, undated.reload.due_on

    patch flash[:undo]["url"]
    assert_nil undated.reload.due_on
    assert_match "moved to no date", flash[:notice]
  end

  test "a to= the buttons never send falls back to today rather than erroring" do
    @task.update!(due_on: 3.days.ago)

    patch reschedule_task_path(@task, to: "2026-02-30") # parses, doesn't exist
    assert_equal Date.current, @task.reload.due_on

    patch reschedule_task_path(@task, to: "next tuesday-ish")
    assert_equal Date.current, @task.reload.due_on
  end

  test "cannot reschedule another user's task" do
    other = users(:two).tasks.create!(title: "Bob's errand", due_on: 3.days.ago)
    patch reschedule_task_path(other, to: "today")
    assert_response :not_found
  end

  test "cannot modify another user's task even when shared" do
    shared = users(:two).tasks.create!(title: "Shared")
    AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: shared)

    get task_path(shared)
    assert_response :success

    patch task_path(shared), params: { task: { title: "Hijacked" } }
    assert_response :not_found
    patch complete_task_path(shared)
    assert_response :not_found
  end

  test "cannot see another user's private task" do
    hidden = users(:two).tasks.create!(title: "Hidden")
    get task_path(hidden)
    assert_response :not_found
  end

  test "destroys own task" do
    assert_difference("Task.count", -1) { delete task_path(@task) }
  end
end
