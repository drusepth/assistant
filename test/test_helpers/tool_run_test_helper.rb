# A draft run lands nothing on its own (D-tool-run-offers): what it would
# create waits on the run page for the user's Add. Tests about a tool's
# *content* — the letter, its follow-ups, its filing — want the rows, so
# this runs the job the way the app does and then clicks "Add everything".
# Tests about the offer flow itself call ToolRunJob directly.
module ToolRunTestHelper
  def run_and_add_all(run)
    ToolRunJob.perform_now(run)
    run.reload.land! if run.reload.done?
  end
end

ActiveSupport.on_load(:active_support_test_case) { include ToolRunTestHelper }
