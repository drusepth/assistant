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

  test "reschedules own task to today or tomorrow" do
    @task.update!(due_on: 3.days.ago)

    patch reschedule_task_path(@task, to: "today")
    assert_equal Date.current, @task.reload.due_on

    patch reschedule_task_path(@task, to: "tomorrow")
    assert_equal Date.tomorrow, @task.reload.due_on
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
