require "test_helper"

class AccessGrantTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @bob = users(:two)
    @carol = users(:outsider)
    @task = @alice.tasks.create!(title: "File taxes")
  end

  test "valid item grant between household members" do
    assert AccessGrant.new(grantor: @alice, grantee: @bob, subject: @task).valid?
  end

  test "valid section grant between household members" do
    assert AccessGrant.new(grantor: @alice, grantee: @bob, subject: sections(:money)).valid?
  end

  test "rejects granting to yourself" do
    grant = AccessGrant.new(grantor: @alice, grantee: @alice, subject: @task)
    assert_not grant.valid?
    assert_includes grant.errors[:grantee], "can't be the grantor"
  end

  test "rejects grants across households" do
    grant = AccessGrant.new(grantor: @alice, grantee: @carol, subject: @task)
    assert_not grant.valid?
    assert_includes grant.errors[:grantee], "must be in the same household"
  end

  test "rejects granting an item the grantor does not own" do
    bobs_task = @bob.tasks.create!(title: "Bob's task")
    grant = AccessGrant.new(grantor: @alice, grantee: @bob, subject: bobs_task)
    assert_not grant.valid?
    assert_includes grant.errors[:subject], "must belong to the grantor"
  end

  test "rejects subject types outside primitives and Section" do
    session = @alice.sessions.create!
    grant = AccessGrant.new(grantor: @alice, grantee: @bob, subject: session)
    assert_not grant.valid?
    assert grant.errors[:subject_type].any?
  end

  test "rejects duplicate grants" do
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @task)
    duplicate = AccessGrant.new(grantor: @alice, grantee: @bob, subject: @task)
    assert_not duplicate.valid?
  end

  test "grants are destroyed with their subject" do
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @task)
    assert_difference("AccessGrant.count", -1) { @task.destroy! }
  end
end
