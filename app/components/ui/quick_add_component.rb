module Ui
  # A page-header quick-add button whose capture form opens as a dropdown
  # panel anchored beneath it (a bottom sheet on small screens). Requires an
  # enclosing `data-controller="quick-add"` element, which coordinates
  # one-open-at-a-time across sibling instances.
  class QuickAddComponent < ApplicationComponent
    def initialize(name:, label:, title:, primary: false)
      @name = name
      @label = label
      @title = title
      @primary = primary
    end

    attr_reader :name, :label, :title

    def button_classes = "btn #{@primary ? "btn-primary" : "btn-secondary"}"
  end
end
