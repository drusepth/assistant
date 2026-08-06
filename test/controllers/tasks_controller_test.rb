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

  test "creates a task with section tags" do
    assert_difference("Task.count") do
      post tasks_path, params: { task: { title: "Budget review", section_ids: [ sections(:money).id ] } }
    end
    assert_equal [ sections(:money) ], Task.last.sections.to_a
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

  test "completes and reopens own task" do
    patch complete_task_path(@task)
    assert @task.reload.completed?
    patch reopen_task_path(@task)
    assert_not @task.reload.completed?
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
