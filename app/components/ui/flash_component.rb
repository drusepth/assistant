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
    # `undo` is an action that rides *inside* the notice describing it, and
    # `follow_up` a link to the obvious next step (a contact that was just
    # made from a bare name wants a birthday and a phone).
    SILENT = %w[ celebrate undo follow_up ].freeze

    def render? = messages.any?

    def messages
      @messages ||= @flash.to_hash.except(*SILENT)
        .map { |type, message| [ type, STYLES.fetch(type, STYLES["notice"]), message ] }
    end

    # `{"label" =>, "url" =>}` — a one-click way back from the action the
    # notice just described. PATCH by default, because most undos are a
    # write that puts a field back where it was; `"method" => "delete"` for
    # the ones that take something back out (a person off the circle).
    def undo = @flash[:undo]

    def undo_method = (undo["method"] || "patch").to_sym

    # `{"label" =>, "url" =>}`, a plain link.
    def follow_up = @flash[:follow_up]
  end
end
