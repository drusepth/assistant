require "test_helper"

# Deleting a user is the one operation that touches nearly every table in the
# app — the household reset (D-household-reset) and "remove member" both come
# down to it — and it is the operation nobody exercises until a real household
# has real data in it. A missing `dependent:` is invisible everywhere else and
# a 500 here.
class UserDestroyTest < ActiveSupport::TestCase
  setup do
    @alice = users(:one)
    @bob = users(:two)
  end

  # **Found, not listed**, the same argument as the reset's blob purge: a
  # hand-written list of what has to cascade is a list that goes stale, and
  # this one went stale twice (the error log, then the vault's audit trail).
  # So ask the schema instead. Every foreign key pointing at a user or a
  # household has to be answered by an association that says what happens to
  # those rows — or by the database itself, if the column was declared with
  # its own ON DELETE. A table added next month is covered by this test the
  # day its migration lands, with nothing to remember.
  test "every foreign key into users and households says what a delete does to it" do
    uncovered = user_foreign_keys.reject { |fk| covered?(fk) }

    assert_empty uncovered.map { |table, column, to_table|
      "#{table}.#{column} -> #{to_table} has no association with a `dependent:` option " \
        "(and no ON DELETE), so destroying a #{to_table.singularize} trips the constraint"
    }
  end

  # The concrete case behind the rule above: a vault audit line names three
  # users — whose vault it is, who acted, and who it was done to — and only
  # the first of the three used to cascade. Sharing a password with your
  # spouse then meant neither of you could be removed.
  test "a member who appears in another member's vault log can still be removed" do
    VaultEvent.record("shared", user: @alice, actor: @alice, subject_user: @bob)
    VaultEvent.record("emergency_requested", user: @alice, actor: @bob)

    assert_difference -> { VaultEvent.count }, -2 do
      assert_nothing_raised { @bob.destroy! }
    end
  end

  # The other end of the same shape, deliberately resolved the other way: an
  # operator still needs last week's failures after the account that hit them
  # is gone, so the log survives with its owner dropped.
  test "the error log outlives the account that hit it, minus the name" do
    error = AppError.record(StandardError.new("boom"), source: "TestJob", user: @bob)

    assert_no_difference -> { AppError.count } do
      @bob.destroy!
    end
    assert_nil error.reload.user_id
  end

  private
    def user_foreign_keys
      connection = ActiveRecord::Base.connection
      connection.tables.flat_map do |table|
        connection.foreign_keys(table)
          .select { |fk| %w[ users households ].include?(fk.to_table) }
          .map { |fk| [ table, fk.column, fk.to_table, fk.on_delete ] }
      end
    end

    def covered?(foreign_key)
      table, column, to_table, on_delete = foreign_key
      return true if on_delete

      owner = to_table.singularize.camelize.constantize
      owner.reflect_on_all_associations.any? do |reflection|
        next false if reflection.belongs_to? || reflection.through_reflection
        next false unless reflection.options[:dependent]

        reflection.klass.table_name == table && reflection.foreign_key.to_s == column
      rescue NameError # an association naming a class that isn't loaded yet
        false
      end
    end
end
