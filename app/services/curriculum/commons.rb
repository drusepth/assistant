module Curriculum
  # The curriculum commons (D-curriculum-commons): core subjects as plain,
  # human-readable YAML in db/curriculum/ — an outline a parent can read in
  # five minutes, diff on GitHub, and edit in a text editor. Enrolling
  # *copies* an outline into the learner's own Subject/Topic tree; the
  # commons itself is never shared reference data.
  class Commons
    Course = Data.define(:key, :title, :description, :strands) do
      def topic_count = strands.sum { |strand| strand.topics.size }
    end
    Strand = Data.define(:title, :topics)
    Entry = Data.define(:title, :summary)

    DIR = Rails.root.join("db/curriculum")

    class << self
      def all
        @all ||= DIR.glob("*.yml").sort.map { |path| load_course(path) }
      end

      def find(key) = all.find { |course| course.key == key.to_s }

      def find!(key)
        find(key) || raise(ActiveRecord::RecordNotFound, "no commons course #{key.inspect}")
      end

      # The learn-anything door checks the shelf first: a typed topic that
      # names a commons course enrolls in it instead of generating.
      def match(text)
        normalized = normalize(text)
        return nil if normalized.blank?

        all.find { |course| normalize(course.title) == normalized || course.key == normalized.tr(" ", "-") }
      end

      # Enrolling instantiates: the outline becomes the learner's own tree,
      # stamped built (there is nothing to generate; personalization is the
      # model's later pass, not a gate).
      def instantiate!(key, user:, interest_frame: nil, target_date: nil)
        course = find!(key)

        Subject.transaction do
          subject = user.subjects.create!(
            title: course.title, description: course.description,
            commons_key: course.key, interest_frame: interest_frame,
            target_date: target_date, tree_built_at: Time.current
          )
          course.strands.each_with_index do |strand, strand_index|
            parent = subject.topics.create!(title: strand.title, position: strand_index + 1)
            strand.topics.each_with_index do |entry, index|
              subject.topics.create!(
                parent: parent, title: entry.title, summary: entry.summary, position: index + 1
              )
            end
          end
          subject
        end
      end

      def reset! = @all = nil

      private
        def load_course(path)
          data = YAML.safe_load_file(path)
          Course.new(
            key: data.fetch("key"),
            title: data.fetch("title"),
            description: data["description"].to_s.strip,
            strands: Array(data["strands"]).map do |strand|
              Strand.new(
                title: strand.fetch("title"),
                topics: Array(strand["topics"]).map do |entry|
                  Entry.new(title: entry.fetch("title"), summary: entry["summary"].to_s.strip)
                end
              )
            end
          )
        end

        def normalize(text) = text.to_s.downcase.gsub(/[^a-z0-9 ]/, " ").squish
    end
  end
end
