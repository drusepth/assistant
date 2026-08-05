module Ui
  class CardComponent < ApplicationComponent
    renders_one :actions

    def initialize(title: nil, subtitle: nil, padded: true)
      @title = title
      @subtitle = subtitle
      @padded = padded
    end

    attr_reader :title, :subtitle

    def header? = title.present? || actions?
    def body_classes = @padded ? "p-5" : ""
  end
end
