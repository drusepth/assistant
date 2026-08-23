module Ui
  class CardComponent < ApplicationComponent
    renders_one :actions

    # count: the number of things inside, shown as a badge beside the title.
    #   A list you have to scroll to the end of to size up isn't scannable —
    #   "Overdue · 7" is the fact you wanted before you started reading.
    #   Zero doesn't draw: an empty list says so in its own body.
    # anchor: an id on the card, so a summary strip above can jump to it.
    def initialize(title: nil, subtitle: nil, count: nil, anchor: nil, padded: true)
      @title = title
      @subtitle = subtitle
      @count = count
      @anchor = anchor
      @padded = padded
    end

    attr_reader :title, :subtitle, :count, :anchor

    def header? = title.present? || actions?
    def body_classes = @padded ? "p-5" : ""
    # The mobile top bar is sticky, so an anchored card has to stop clear of it.
    def card_classes = anchor ? "card scroll-mt-20" : "card"
  end
end
