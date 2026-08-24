module Ui
  class FlashComponent < ApplicationComponent
    STYLES = {
      "notice" => "border-primary-200 bg-primary-50 text-primary-800",
      "alert" => "border-red-200 bg-red-50 text-red-700"
    }.freeze

    def initialize(flash:)
      @flash = flash
    end

    # Flash keys the app uses to carry data rather than a sentence to read —
    # they travel the same redirect, but they are never banners of their own.
    # `undo` is an action that rides *inside* the notice describing it.
    SILENT = %w[ celebrate undo ].freeze

    def render? = messages.any?

    def messages
      @messages ||= @flash.to_hash.except(*SILENT)
        .map { |type, message| [ type, STYLES.fetch(type, STYLES["notice"]), message ] }
    end

    # `{"label" =>, "url" =>}` — a one-click way back from the action the
    # notice just described. PATCH, because every undo the app has is a
    # write that puts a field back where it was.
    def undo = @flash[:undo]
  end
end
