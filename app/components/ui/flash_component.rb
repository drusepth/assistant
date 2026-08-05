module Ui
  class FlashComponent < ApplicationComponent
    STYLES = {
      "notice" => "border-primary-200 bg-primary-50 text-primary-800",
      "alert" => "border-red-200 bg-red-50 text-red-700"
    }.freeze

    def initialize(flash:)
      @flash = flash
    end

    def render? = @flash.any?

    def messages
      @flash.map { |type, message| [ STYLES.fetch(type, STYLES["notice"]), message ] }
    end
  end
end
