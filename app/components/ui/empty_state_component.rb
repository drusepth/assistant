module Ui
  class EmptyStateComponent < ApplicationComponent
    renders_one :action

    def initialize(title:, description: nil)
      @title = title
      @description = description
    end

    attr_reader :title, :description
  end
end
