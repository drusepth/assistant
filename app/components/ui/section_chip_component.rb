module Ui
  class SectionChipComponent < ApplicationComponent
    # qualified: false drops the "Parent · " prefix — for chips rendered
    # where the parent is already the surrounding context (its own page).
    def initialize(section:, qualified: true)
      @section = section
      @qualified = qualified
    end

    attr_reader :section

    def label
      @qualified ? section.qualified_name : section.name
    end
  end
end
