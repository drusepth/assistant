module Ui
  class PageHeaderComponent < ApplicationComponent
    renders_one :actions

    def initialize(title:, subtitle: nil)
      @title = title
      @subtitle = subtitle
    end

    attr_reader :title, :subtitle
  end
end
