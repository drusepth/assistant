require "test_helper"

# Schema-wide conventions, enforced rather than remembered
# (D-flavor-columns-not-null).
class SchemaConventionsTest < ActiveSupport::TestCase
  # Columns that name which *sort* of row this is — the ones code branches and
  # filters on. They must be NOT NULL, so that the plain case has a name.
  FLAVOR_COLUMNS = %w[ kind kind_key status group ].freeze

  # Tables whose flavor column is genuinely optional, each with the reason.
  # Empty on purpose: add to it only when NULL carries meaning a name can't.
  EXEMPT = {}.freeze

  test "every flavor column is NOT NULL, so the plain case has a name" do
    offenders = connection.tables.flat_map do |table|
      connection.columns(table)
        .select { |column| column.name.in?(FLAVOR_COLUMNS) && column.null }
        .reject { |column| EXEMPT[[ table, column.name ]] }
        .map { |column| "#{table}.#{column.name}" }
    end

    assert_empty offenders, <<~WHY
      These columns let NULL stand in for the plain case. In SQL that is a trap,
      not a shorthand: `kind != 'allergy'` evaluates to NULL — not true — for
      every row where kind IS NULL, so a negated query silently drops all of
      them. That is the bug that emptied the doctor-visit-prep notes block
      (D-allergy-notes), and notes.kind was the only column in the schema
      shaped that way.

      Fix it in the schema, not at the call sites: backfill a named default
      ("plain", "none", "other" — whatever the plain case is actually called),
      then `change_column_null ..., false`. Six other kind columns already do
      this (credentials "login", feeds "rss", spending_accounts "checking",
      suggestions "nudge").

      If NULL genuinely means something a name cannot — an unanswered question
      rather than a value, the way notes.severity means "not sure" — that is not
      a flavor column; keep it optional and add it to EXEMPT with the reason.
    WHY
  end

  private
    def connection = ActiveRecord::Base.connection
end
