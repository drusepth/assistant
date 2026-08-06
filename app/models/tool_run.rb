# One tool invocation and its paper trail (D19): the inputs the user gave,
# where the run stands, and the primitives it created. The show page doubles
# as the live progress surface and history — "the letter I drafted in March."
# Runs are the owner's private surface (no Visible): the primitives a run
# creates follow the normal sharing rules on their own pages.
class ToolRun < ApplicationRecord
  belongs_to :user
  has_many :tool_run_items, dependent: :destroy

  enum :status, { queued: "queued", running: "running", done: "done", failed: "failed" }, default: :queued

  validates :tool_slug, inclusion: { in: Tool::SLUGS }
  validate :required_inputs_present, on: :create

  def tool = Tool.find!(tool_slug)

  def items
    tool_run_items.includes(:item).map(&:item).compact
  end

  NextStep = Data.define(:tool, :inputs, :reason)

  # Follow-on tools this run proposed (D21) — sanitized at write time by
  # Tool::Base#store_next_tools, re-resolved against the registry at read
  # time so a retired slug can never break the page.
  def next_steps
    Array(output["next_tools"]).filter_map do |entry|
      next unless entry.is_a?(Hash)

      tool = Tool.find(entry["slug"])
      NextStep.new(tool: tool, inputs: entry["inputs"] || {}, reason: entry["reason"]) if tool
    end
  end

  def finished? = done? || failed?

  private
    def required_inputs_present
      return unless (tool = Tool.find(tool_slug))

      tool.inputs.select(&:required?).each do |input|
        errors.add(:base, "“#{input.label}” needs an answer.") if inputs[input.name].blank?
      end
    end
end
