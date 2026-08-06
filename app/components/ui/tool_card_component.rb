module Ui
  # A tool's card in a section page's Act zone (D18): what it does, one
  # click to its run form.
  class ToolCardComponent < ApplicationComponent
    def initialize(tool:)
      @tool = tool
    end

    attr_reader :tool
  end
end
