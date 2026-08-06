require "test_helper"

class VisibilityTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @bob = users(:two)
    @money = sections(:money)
    @task = @alice.tasks.create!(title: "File taxes")
  end

  test "owner sees their own items" do
    assert_includes Task.visible_to(@alice), @task
    assert @task.visible_to?(@alice)
  end

  test "household member sees nothing without a grant" do
    assert_empty Task.visible_to(@bob)
    assert_not @task.visible_to?(@bob)
  end

  test "item grant makes exactly that item visible" do
    other_task = @alice.tasks.create!(title: "Private errand")
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @task)

    assert_includes Task.visible_to(@bob), @task
    assert_not_includes Task.visible_to(@bob), other_task
  end

  test "section grant exposes the grantor's items tagged with that section" do
    @task.sections << @money
    untagged = @alice.tasks.create!(title: "Untagged errand")
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @money)

    assert_includes Task.visible_to(@bob), @task
    assert_not_includes Task.visible_to(@bob), untagged
  end

  test "section grant covers items tagged after the grant was created" do
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @money)
    assert_not @task.visible_to?(@bob)

    @task.sections << @money
    assert @task.visible_to?(@bob)
  end

  test "section grant does not expose other users' items in that section" do
    bobs_task = @bob.tasks.create!(title: "Bob's budget review")
    bobs_task.sections << @money
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @money)

    assert_not_includes Task.visible_to(@alice), bobs_task
  end

  test "grants are scoped to the primitive type" do
    event = @alice.events.create!(title: "Dentist", starts_at: 1.week.from_now)
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @task)

    assert_not_includes Event.visible_to(@bob), event
  end

  test "visible_to composes with in_section" do
    @task.sections << @money
    AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @task)

    assert_includes Task.visible_to(@bob).in_section(@money), @task
    assert_empty Task.visible_to(@bob).in_section(sections(:health))
  end

  test "revoking a grant removes visibility" do
    grant = AccessGrant.create!(grantor: @alice, grantee: @bob, subject: @task)
    assert @task.visible_to?(@bob)

    grant.destroy!
    assert_not @task.visible_to?(@bob)
  end
end
