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

  # A hub degrades gracefully without prose (generated tool cards carry it),
  # but a top-level page and a feature page are nothing *but* their prose.
  # Registering one without its partial ships a masthead over an exception,
  # so the registry and the views are pinned to each other here — with a
  # message that names the missing file rather than failing as a render.
  test "every prose-only page has its partial" do
    missing = {
      "topics" => About::Page::TOP_LEVEL,
      "features" => About::Page::FEATURES
    }.flat_map do |directory, pages|
      pages.filter_map do |page|
        path = "app/views/about/#{directory}/_#{page.slug.tr('-', '_')}.html.erb"
        path unless Rails.root.join(path).exist?
      end
    end

    assert_empty missing, <<~MSG
      These pages are registered but have no prose, and have nothing
      generated to fall back on. Write the partial, or drop the registry row
      until you do (docs/ABOUT_PLAN.md §8):

      #{missing.join("\n")}
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
