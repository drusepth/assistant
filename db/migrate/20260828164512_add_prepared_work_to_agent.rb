# D-agent-prepared-work: "Active" starts meaning the agent arrives with the
# work already done. Three columns and no new table — a prepared draft is an
# ordinary tool run whose landings are still intents.
class AddPreparedWorkToAgent < ActiveRecord::Migration[8.1]
  def change
    # The draft waiting on a suggestion. Nullable and nullify-on-delete:
    # every suggestion without one behaves exactly as it did before, which
    # is also what a failed preparation degrades back to.
    add_reference :suggestions, :tool_run, null: true, foreign_key: { on_delete: :nullify }

    # Who asked for this run. Agent runs render labeled wherever runs
    # appear, and the Settings transparency line counts them.
    add_column :tool_runs, :origin, :string, null: false, default: "user"

    # The one switch over preparation itself (the dial already decides
    # *which* sections may prepare). Default on: Active is opt-in already,
    # and a dial that means "come to me" has answered this question.
    add_column :users, :prepare_work, :boolean, null: false, default: true
  end
end
