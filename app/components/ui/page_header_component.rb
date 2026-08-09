module Ui
  class PageHeaderComponent < ApplicationComponent
    renders_one :actions

    # A line under the subtitle for who this belongs to — "shared by Bea,
    # read-only". A slot rather than more subtitle string, because the thing
    # it renders is an avatar and a name, not text.
    renders_one :meta

    def initialize(title:, subtitle: nil)
      @title = title
      @subtitle = subtitle
    end

    attr_reader :title, :subtitle
  end
end
