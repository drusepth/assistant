require "test_helper"

class AccessGrantsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @task = users(:one).tasks.create!(title: "Shareable")
  end

  test "creates an item grant" do
    assert_difference("AccessGrant.count") do
      post access_grants_path, params: { subject_type: "Task", subject_id: @task.id, grantee_id: users(:two).id }
    end
    assert @task.visible_to?(users(:two))
  end

  test "creates a section grant" do
    assert_difference("AccessGrant.count") do
      post access_grants_path, params: { subject_type: "Section", subject_id: sections(:money).id, grantee_id: users(:two).id }
    end
  end

  test "rejects a cross-household grantee" do
    assert_no_difference("AccessGrant.count") do
      post access_grants_path, params: { subject_type: "Task", subject_id: @task.id, grantee_id: users(:outsider).id }
    end
  end

  test "rejects unsupported subject types" do
    session_record = users(:one).sessions.create!
    assert_no_difference("AccessGrant.count") do
      post access_grants_path, params: { subject_type: "Session", subject_id: session_record.id, grantee_id: users(:two).id }
    end
    assert_response :not_found
  end

  test "revokes own grants but not someone else's" do
    grant = AccessGrant.create!(grantor: users(:one), grantee: users(:two), subject: @task)
    assert_difference("AccessGrant.count", -1) { delete access_grant_path(grant) }

    bobs_task = users(:two).tasks.create!(title: "Bob's")
    bobs_grant = AccessGrant.create!(grantor: users(:two), grantee: users(:one), subject: bobs_task)
    delete access_grant_path(bobs_grant)
    assert_response :not_found
    assert AccessGrant.exists?(bobs_grant.id)
  end
end
