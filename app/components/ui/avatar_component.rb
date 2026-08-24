module Ui
  # One face, one place (D-user-avatars). Every surface that says *who
  # someone is* renders through this: the uploaded photo when there is one,
  # the initials circle that was always there when there isn't — so an
  # instance where nobody has uploaded anything looks exactly as it did.
  #
  # Takes a user, a person, and/or a name. A Person row passes the person
  # (`person: person`) and the component sorts out whose face to draw: the
  # contact's own photo first (D-contact-photos), the linked household
  # member's next (D8), the contact's initials when there is neither — so
  # nothing ever borrows a face it wasn't given.
  class AvatarComponent < ApplicationComponent
    SIZES = {
      # Small enough to sit inside a calendar pill without growing the row.
      xxs: "size-4 text-[0.5rem]",
      xs: "size-6 text-[0.625rem]",
      sm: "size-8 text-xs",
      md: "size-10 text-sm",
      lg: "size-14 text-base",
      xl: "size-20 text-xl"
    }.freeze

    # Only the fallback is tinted — an uploaded photo brings its own color.
    TONES = {
      primary: "bg-primary-100 text-primary-800",
      amber: "bg-amber-100 text-amber-800",
      stone: "bg-stone-100 text-stone-700"
    }.freeze

    def initialize(user: nil, person: nil, name: nil, size: :md, tone: :primary, css_class: nil, title: nil)
      @person = person
      @user = user || person&.linked_user
      # Whoever actually has a renderable photo, contact first; failing
      # that, whoever the circle is *about*, for the initials.
      @subject = [ person, @user ].compact.find(&:avatar_ready?) || person || @user
      @name = name.presence || person&.name || @user&.name
      @size = size
      @tone = tone
      @css_class = css_class
      @title = title
    end

    attr_reader :person, :user, :name, :title

    def image? = @subject&.avatar_ready?

    # `helpers.` on purpose: variant URLs are polymorphic routes, and the
    # parent view context is the one guaranteed to resolve them.
    def image_url = helpers.url_for(@subject.avatar.variant(:thumb))

    def initials = @subject&.initials.presence || name.to_s.split.map { |word| word.chars.first }.join[0, 2].upcase

    def classes
      [ "flex shrink-0 items-center justify-center overflow-hidden rounded-full font-semibold",
        SIZES.fetch(@size), (TONES.fetch(@tone) unless image?), @css_class ].compact.join(" ")
    end
  end
end
