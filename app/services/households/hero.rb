module Households
  # The dashboard's opening line (D-household-profile): who you are, not what
  # you owe. Every other surface in the app is a worklist — this one is the
  # household looking back at you, and it is deliberately computed from data
  # the household already has (no LLM call, no network, nothing to configure
  # before it says something warm).
  #
  # The rule for a highlight: it must be true today and about *this*
  # household. No streaks, no scores, no manufactured milestones — a
  # celebration you didn't earn reads as noise by the third visit.
  class Hero
    # A highlight: an icon, a line, and optionally somewhere to go.
    Highlight = Struct.new(:icon, :text, :detail, :path, keyword_init: true)

    def initialize(viewer, on: Date.current, now: Time.current)
      @viewer = viewer
      @on = on
      @now = now
    end

    attr_reader :viewer, :on, :now

    def household = @household ||= viewer.household

    def greeting
      case now.hour
      when 0...5   then "Still up"
      when 5...12  then "Good morning"
      when 12...17 then "Good afternoon"
      when 17...22 then "Good evening"
      else              "Good night"
      end
    end

    def first_name = viewer.name.to_s.split.first.presence || viewer.name

    def members = @members ||= household.users.order(:name)

    def banner = household.banner

    # At most three, most personal first: a birthday beats an anniversary
    # beats a photo memory. A quiet day gets none, and the hero simply
    # greets you — that is a fine outcome, not an empty state to fill.
    def highlights = @highlights ||= (birthday_highlights + anniversary_highlights + memory_highlights).first(3)

    # The one photo behind a memory highlight, so the partial can show it.
    def memory_photo
      return @memory_photo if defined?(@memory_photo)

      @memory_photo = Photo.visible_to(viewer).ingest_ready
        .where("strftime('%m-%d', taken_at) = ?", on.strftime("%m-%d"))
        .where(taken_at: ...on.beginning_of_year)
        .order(taken_at: :desc).first
    end

    # The quiet footer facts: what this household is, in three numbers or
    # fewer. Blank entries drop out rather than showing a zero.
    def facts
      [
        (pluralize_fact(members.size, "member") if members.size > 1),
        household.region.presence,
        ("Home since #{household.moved_in_on.year}" if household.moved_in_on)
      ].compact
    end

    private
      def birthday_highlights
        today, soon = upcoming_birthdays.partition { |person| person.next_birthday(from: on) == on }

        today.map do |person|
          Highlight.new(icon: :flag, text: "It's #{person.name}'s birthday today", path: person_path(person))
        end + soon.first(1).map do |person|
          days = (person.next_birthday(from: on) - on).to_i
          Highlight.new(icon: :flag, text: "#{person.name}'s birthday #{days == 1 ? "is tomorrow" : "is in #{days} days"}",
            path: person_path(person))
        end
      end

      # The circle only (D-people-dashboard): an imported address book must
      # not turn the hero into a birthday firehose.
      def upcoming_birthdays
        @upcoming_birthdays ||= viewer.people.circle.birthday_within(7, from: on)
      end

      def anniversary_highlights
        return [] unless household.home_anniversary?(on: on)

        years = household.years_at_home(on: on)
        [ Highlight.new(icon: :home, text: "#{pluralize_fact(years, "year")} in this home today",
            detail: "Moved in #{household.moved_in_on.strftime("%B %-d, %Y")}") ]
      end

      def memory_highlights
        return [] unless memory_photo

        years = on.year - memory_photo.taken_at.year
        [ Highlight.new(icon: :photo, text: "#{pluralize_fact(years, "year")} ago today",
            detail: memory_photo.title.presence || memory_photo.caption.presence, path: photo_path(memory_photo)) ]
      end

      def pluralize_fact(count, noun) = "#{count} #{noun}#{"s" unless count == 1}"

      def person_path(person) = Rails.application.routes.url_helpers.person_path(person)
      def photo_path(photo) = Rails.application.routes.url_helpers.photo_path(photo)
  end
end
