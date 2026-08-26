module People
  # The Address Book's shape (D-address-book-directory). The roster is the
  # one People surface that has to still work the morning after a CardDAV
  # import drops four hundred contacts into it, so the things that decide
  # whether it does — the search, the filters, and the A–Z grouping — live
  # here rather than in the view, and every count on the page comes off a
  # batched query rather than one per chip.
  #
  # Deliberately *not* the People section page's job: that page is the
  # circle's dashboard (D-people-dashboard) and answers "who should I reach
  # out to". This one answers "how do I reach Rosa", which is a different
  # question and wants a directory, not cards.
  class Directory
    # Names that don't start with a letter — "이준", "3rd Street Clinic" —
    # get their own bucket rather than being dropped or filed under a wrong
    # letter. An address book that loses a row is worse than one with a `#`.
    OTHER = "#".freeze
    LETTERS = ("A".."Z").to_a.freeze
    # Everything a typed query is matched against, in SQL. Address and notes
    # are in here because "the woman on Cedar Street" is how people actually
    # look someone up.
    SEARCHABLE = %w[ name relationship email phone address notes ].freeze

    Letter = Struct.new(:key, :people, keyword_init: true) do
      def anchor = "letter-#{key == OTHER ? "other" : key.downcase}"
      def label = key
    end

    def initialize(viewer, query: nil, circle: false, group_slug: nil)
      @viewer = viewer
      @query = query.to_s.strip
      @circle = circle
      @group_slug = group_slug.presence
    end

    attr_reader :viewer, :query

    def circle? = @circle
    def filtered? = query.present? || circle? || group.present?

    # The one selected group lens, when the URL named a real one. An unknown
    # slug filters nothing rather than 404ing — a stale bookmark to a group
    # somebody deleted should still show you your address book.
    def group
      return @group if defined?(@group)
      @group = @group_slug && groups.find { |section| section.slug == @group_slug }
    end

    def people = @people ||= load_people

    def total = people.size

    # A–Z, then `#`, and only the buckets that actually hold somebody: an
    # empty heading is a promise the list doesn't keep.
    def letters
      @letters ||= begin
        buckets = people.group_by { |person| self.class.letter_for(person.name) }
        (LETTERS + [ OTHER ]).filter_map do |key|
          Letter.new(key: key, people: buckets[key]) if buckets[key]
        end
      end
    end

    def letter_present?(key) = letters.any? { |letter| letter.key == key }

    # Every group that holds at least one person this viewer can see, with
    # its count. A chip that leads to an empty page is worse than no chip,
    # so empty groups don't appear here — they live on the People page,
    # where a new one is meant to look like an invitation.
    def group_chips
      @group_chips ||= groups.filter_map do |section|
        count = group_counts[section.id]
        [ section, count ] if count&.positive?
      end
    end

    def circle_size = @circle_size ||= viewer.people.circle.count

    # Total roster size regardless of the filters, for the header line —
    # "12 of 431" only reads if the 431 is there.
    def roster_size = @roster_size ||= Person.visible_to(viewer).count

    def self.letter_for(name)
      first = name.to_s.strip.first.to_s.upcase
      LETTERS.include?(first) ? first : OTHER
    end

    private
      def groups
        @groups ||= Section.find_by(slug: "people")&.children.to_a
      end

      def load_people
        # The circle is per-user intent, so circle mode never reaches past
        # your own contacts (D-people-dashboard); everything else reads
        # through the one authorized path (D9).
        scope = circle? ? viewer.people.circle : Person.visible_to(viewer)
        scope = scope.in_section(group) if group
        scope = scope.where(search_clause, needle: "%#{Person.sanitize_sql_like(query)}%") if query.present?
        # NOCASE, or SQLite's binary collation files every lowercase name
        # after Zoe — which is exactly the bug an alphabetized page exists
        # to not have.
        scope.includes(:sections, :user, :linked_user)
          .with_attached_avatar
          .order(Arel.sql("people.name COLLATE NOCASE ASC"))
          .to_a
      end

      def search_clause
        @search_clause ||= SEARCHABLE.map { |column| "people.#{column} LIKE :needle" }.join(" OR ")
      end

      # One query for every chip's count, not one per chip: this is the row
      # that silently degrades the day somebody makes twenty groups.
      def group_counts
        @group_counts ||= begin
          return {} if groups.empty?

          SectionTagging.where(taggable_type: "Person", section_id: groups.map(&:id))
            .where(taggable_id: Person.visible_to(viewer).select(:id))
            .group(:section_id).count
        end
      end
  end
end
