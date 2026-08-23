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
    # they travel the same redirect, but they are never banners.
    SILENT = %w[ celebrate ].freeze

    def render? = messages.any?

    def messages
      @messages ||= @flash.to_hash.except(*SILENT)
        .map { |type, message| [ STYLES.fetch(type, STYLES["notice"]), message ] }
    end
  end
end
