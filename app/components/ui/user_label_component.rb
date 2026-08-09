module Ui
  # Avatar + name, the inline pair (D-user-avatars). Wherever the app names
  # a person mid-sentence — "from Bea", "shared by Bea — read-only", a row
  # in a sharing list — this is the shape, so the pair stays one decision
  # instead of fourteen copies of the same flex span.
  #
  # The label is block content, because the wording around the name is what
  # varies ("from", "by", "shared by") and a `prefix:` option would only be
  # a worse way to spell the same string. No block falls back to the name.
  class UserLabelComponent < ApplicationComponent
    def initialize(user: nil, name: nil, size: :xs, css_class: nil, truncate: false)
      @user = user
      @name = name.presence || user&.name
      @size = size
      @css_class = css_class
      @truncate = truncate
    end

    attr_reader :user, :name, :size

    def wrapper_classes = [ "inline-flex min-w-0 items-center gap-1.5", @css_class ].compact.join(" ")

    def text_classes = @truncate ? "min-w-0 truncate" : nil
  end
end
