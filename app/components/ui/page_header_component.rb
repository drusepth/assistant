module Ui
  class PageHeaderComponent < ApplicationComponent
    renders_one :actions

    # A line under the subtitle for who this belongs to — "shared by Bea,
    # read-only". A slot rather than more subtitle string, because the thing
    # it renders is an avatar and a name, not text.
    renders_one :meta

    # A face to the left of the title, on the pages that are *about* a
    # person — a contact, a household member (D-contact-photos).
    renders_one :avatar

    def initialize(title:, subtitle: nil)
      @title = title
      @subtitle = subtitle
    end

    attr_reader :title, :subtitle
  end
end
