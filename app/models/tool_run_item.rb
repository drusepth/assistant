# Joins a run to the primitives it created, so the run page can show its
# results and history stays inspectable after the fact.
class ToolRunItem < ApplicationRecord
  belongs_to :tool_run
  belongs_to :item, polymorphic: true
end
