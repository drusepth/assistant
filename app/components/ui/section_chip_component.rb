module Ui
  class SectionChipComponent < ApplicationComponent
    def initialize(section:)
      @section = section
    end

    attr_reader :section
  end
end
