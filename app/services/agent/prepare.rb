module Agent
  # Runs a suggestion's tool ahead of the click and parks the result on the
  # suggestion (D-agent-prepared-work). The tool class, its prompt, its
  # visibility-walled context and its filing are all exactly what an
  # ordinary invocation would use — the only difference is that the landing
  # helpers write intents into `output["landings"]` instead of rows.
  #
  # Nothing here is user-visible when it goes wrong. A failure leaves the
  # suggestion precisely as M3 built it — a prefilled redirect to the form —
  # so preparation is pure upside or invisible, never an apology.
  class Prepare
    def initialize(suggestion)
      @suggestion = suggestion
      @user = suggestion.user
    end

    def call
      tool = suggestion.preparable_tool
      return if tool.nil? || suggestion.tool_run.present?
      # The scan enqueued this; between then and now the retire pass, or the
      # user, may have settled the matter. Drafting for a nudge that is
      # already gone would spend tokens on work nobody will ever be shown.
      return unless suggestion.reload.pending?

      run = user.tool_runs.create!(
        tool_slug: tool.slug, inputs: suggestion.tool_action["inputs"] || {},
        origin: :agent, status: :running
      )

      begin
        landings, output = execute(tool, run)
        # A tool that produced no intents prepared nothing worth showing —
        # including one that creates its primitives outside the landing
        # helpers, whose writes the rollback below has just undone. Either
        # way the honest result is no prepared draft at all.
        return discard(run) if landings.empty?

        run.update!(status: :prepared, output: output.merge("landings" => landings))
        suggestion.update!(tool_run: run)
      rescue StandardError
        discard(run)
        raise
      end
    end

    private
      attr_reader :suggestion, :user

      # The structural guarantee that a speculative run leaves nothing
      # behind: everything the tool touches happens inside a transaction
      # that is always rolled back. The landings survive because they are an
      # in-memory array, not rows. This is deliberately a property of the
      # *runner* rather than a rule tools are trusted to follow — a tool
      # added next year that writes a primitive directly is safe here
      # without knowing preparation exists.
      #
      # The open transaction spans the model call, but the call writes
      # nothing, so no write lock is held while it waits.
      def execute(tool, run)
        run.preparing = true
        landings = []
        output = {}

        ActiveRecord::Base.transaction do
          instance = tool.new(run)
          instance.call
          landings = instance.landings
          output = run.output
          raise ActiveRecord::Rollback
        end

        [ landings, output ]
      ensure
        run.preparing = false
      end

      # A run nobody asked for that produced nothing is clutter in the
      # user's history, so it goes away entirely rather than sitting there
      # as a failure they never triggered.
      def discard(run)
        suggestion.update!(tool_run: nil) if suggestion.tool_run_id == run.id
        run.destroy!
        nil
      end
  end
end
