require "test_helper"

# Source-level pins on the /about prose — the failures a request test can't
# see, because the page renders fine and only *reads* wrong.
class AboutContentTest < ActiveSupport::TestCase
  VIEWS = Rails.root.glob("app/views/about/**/*.erb") +
    [ Rails.root.join("app/views/layouts/about.html.erb") ]

  # The public vocabulary rule (docs/ABOUT_PLAN.md §6): the reader is the
  # 99%, so the words we use to build the app never appear on the pages
  # that explain it. "Sections" and "household" are public words; these are
  # not. ERB comments are exempt — they're for the next builder, who is
  # exactly who architecture words are for.
  JARGON = %w[ lens lenses primitive primitives sectionable polymorphic
               taxonomy LLM kanban ].freeze

  test "no architecture word reaches a visitor" do
    offenders = VIEWS.flat_map do |path|
      prose_lines(path).filter_map do |line, number|
        word = JARGON.find { |jargon| line.match?(/\b#{Regexp.escape(jargon)}\b/i) }
        "#{path.relative_path_from(Rails.root)}:#{number} — #{word}" if word
      end
    end

    assert_empty offenders, <<~MSG
      These lines use builder vocabulary on a visitor-facing page. Say what
      the thing does in plain words, or move the term into an ERB comment:

      #{offenders.join("\n")}
    MSG
  end

  # Facts the prose states that no template can compute — a class name
  # can't become "the password vault". So the fact is pinned instead:
  # growing the registry turns the stale page into a red test that names
  # every page to update, rather than a lie nobody notices.
  test "the sealed containers are the two the pages name" do
    assert_equal %w[ Credential DiaryEntry ], VaultSealed::CONTAINERS.sort, <<~MSG
      A sealed container was added or removed. These pages name the set in
      prose ("the password vault and the diary") — update them, then this
      pin:

        app/views/about/topics/_privacy.html.erb
        app/views/about/sections/_your_stuff.html.erb
    MSG
  end

  private
    # Lines with their ERB comments stripped, so a term in a `<%# ... %>`
    # aside never counts against the page. Multi-line comments open with
    # `<%#` and run to the closing `%>`.
    def prose_lines(path)
      in_comment = false
      path.readlines.each_with_index.filter_map do |line, index|
        stripped = line.gsub(/<%#.*?%>/m, "")
        if in_comment
          next (in_comment = false) && nil if stripped.include?("%>")
          next
        end
        if stripped.include?("<%#")
          stripped = stripped.sub(/<%#.*/m, "")
          in_comment = true
        end
        [ stripped, index + 1 ] if stripped.present?
      end
    end
end
