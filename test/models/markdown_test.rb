require "test_helper"

# The renderer's whole safety argument is "everything is escaped before a
# single rule runs", so most of this file is attempts to get a tag past it.
class MarkdownTest < ActiveSupport::TestCase
  def render(text) = Markdown.render(text)

  # --- the safety argument ---

  test "typed HTML renders as text, not as markup" do
    html = render("<script>alert(1)</script> and <b>bold</b>")

    assert_no_match(/<script/i, html)
    assert_no_match(/<b>/, html)
    assert_match "&lt;script&gt;", html
  end

  test "an img with an onerror handler is text" do
    html = render(%(<img src=x onerror="alert(1)">))

    assert_no_match(/<img/i, html)
    assert_equal %(<p>&lt;img src=x onerror=&quot;alert(1)&quot;&gt;</p>), html,
      "the whole thing must survive as visible text — escaped, and inside a paragraph"
  end

  test "a javascript: link keeps its source and gains no href" do
    html = render("[click me](javascript:alert(1))")

    # The words "javascript:" appearing as *text* is fine and correct; what
    # must not exist is an attribute carrying them.
    assert_no_match(/<a /, html)
    assert_no_match(/href=/i, html)
    assert_match "[click me]", html
  end

  test "data: and scheme-relative targets are refused too" do
    %w[ data:text/html;base64,PHNjcmlwdD4= //evil.example/x vbscript:msgbox ].each do |url|
      assert_no_match(/<a /, render("[x](#{url})"), "#{url} must not become a link")
    end
  end

  test "an http link is rendered, and cannot break out of its attribute" do
    html = render('[home](https://example.com/a?b=1&c=2) and [bad](https://example.com/")')

    assert_match %(href="https://example.com/a?b=1&amp;c=2"), html
    assert_match %(rel="noopener noreferrer nofollow"), html
    assert_no_match(/href="https:\/\/example\.com\/"">/, html)
  end

  test "a link label cannot smuggle markup" do
    html = render("[<script>x</script>](https://example.com)")

    assert_no_match(/<script/i, html)
    assert_match "&lt;script&gt;", html
  end

  test "output is marked safe only after escaping" do
    assert_predicate render("plain"), :html_safe?
    assert_no_match(/<script/i, render("`<script>`"))
  end

  # --- the markdown a diary actually uses ---

  test "paragraphs, and single newlines as line breaks" do
    html = render("One line\nnext line\n\nA second paragraph.")

    assert_equal 2, html.scan("<p>").length
    assert_match "One line<br>next line", html
  end

  test "headings start below the page title" do
    html = render("# Big\n\n## Middle\n\n### Small")

    assert_match "<h2>Big</h2>", html
    assert_match "<h3>Middle</h3>", html
    assert_match "<h4>Small</h4>", html
  end

  test "bold, italic and code spans" do
    html = render("**bold** and *italic* and _also italic_ and `code`")

    assert_match "<strong>bold</strong>", html
    assert_equal 2, html.scan("<em>").length
    assert_match "<code>code</code>", html
  end

  test "an asterisk inside a word is not italics" do
    assert_no_match(/<em>/, render("2 * 3 * 4"))
    assert_no_match(/<em>/, render("snake_case_name stays put"))
  end

  test "markdown inside a code span is left alone" do
    html = render("`**not bold**`")

    assert_match "<code>**not bold**</code>", html
    assert_no_match(/<strong>/, html)
  end

  test "bulleted and numbered lists" do
    bulleted = render("- one\n- two")
    numbered = render("1. first\n2. second")

    assert_match "<ul><li>one</li><li>two</li></ul>", bulleted
    assert_match "<ol><li>first</li><li>second</li></ol>", numbered
  end

  test "blockquotes" do
    assert_match "<blockquote>a quote</blockquote>", render("> a quote")
  end

  test "a fenced block keeps its characters and runs no inline rules" do
    html = render("```\n**literal** <b>tags</b>\n```")

    assert_match "<pre><code>**literal** &lt;b&gt;tags&lt;/b&gt;</code></pre>", html
    assert_no_match(/<strong>/, html)
  end

  test "an unclosed fence does not swallow the renderer" do
    assert_nothing_raised { render("```\nstill typing") }
  end

  # --- the shapes real writing takes ---

  test "plain prose with no markdown comes through unchanged" do
    html = render("Just a normal day. Nothing special happened, and that was fine.")

    assert_match "<p>Just a normal day. Nothing special happened, and that was fine.</p>", html
  end

  test "empty and whitespace-only bodies render nothing rather than failing" do
    assert_equal "", render("")
    assert_equal "", render("   \n\n  ")
    assert_equal "", render(nil)
  end

  test "windows line endings behave like any others" do
    assert_match "<p>One<br>Two</p>", render("One\r\nTwo")
  end

  # --- the shapes a model's draft takes ---

  test "deeper headings all become the smallest marker" do
    assert_match "<h4>Deep</h4>", render("#### Deep")
    assert_match "<h3>Closed</h3>", render("## Closed ##")
  end

  test "a table with a header renders as one, with each cell labelled by its column" do
    html = render("| Who | Why |\n|---|---|\n| **Vet** | They check the chip |")

    assert_match "<thead><tr><th>Who</th><th>Why</th></tr></thead>", html
    assert_match %(<td data-label="Who"><strong>Vet</strong></td>), html
    assert_match %(<td data-label="Why">They check the chip</td>), html
    assert_match %(<div class="prose-table">), html
  end

  test "a row a model broke across lines to fit a list in a cell stays one row" do
    html = render(<<~MD)
      | Organisation | What to give them | Why |
      |---|---|---|
      | **Microchip registry** | • Microchip number
      • Description
      • Last seen | Flag him as missing. |
      | Shelters | Description | They can alert staff. |
    MD

    assert_equal 2, html.scan("<tr><td").length
    assert_match "<ul><li>Microchip number</li><li>Description</li><li>Last seen</li></ul>", html
    assert_match "Flag him as missing.", html
    assert_no_match(/<p>/, html, "no row may leak out of the table as a paragraph")
  end

  test "a literal br inside a cell is a line break, and nothing else typed there is markup" do
    html = render("| A | B |\n|---|---|\n| one<br>two | <b>x</b> |")

    assert_match "one<br>two", html
    assert_match "&lt;b&gt;x&lt;/b&gt;", html
  end

  test "a header label cannot break out of its attribute" do
    html = render(%(| "><script> |\n|---|\n| x |))

    assert_no_match(/<script/i, html)
    assert_match %(data-label="&quot;&gt;&lt;script&gt;"), html
  end

  test "indented sub-points nest under their item, and wrapped lines join it" do
    html = render("- Poster\n  - name\n  - photo\n- Posts\n  on every group")

    assert_match "<ul><li>Poster<ul><li>name</li><li>photo</li></ul></li><li>Posts<br>on every group</li></ul>", html
  end

  test "numbered steps split by blank lines keep counting" do
    html = render("1. Search the house\n\n2. Take a torch")

    assert_match "<ol><li>Search the house</li></ol>", html
    assert_match %(<ol start="2"><li>Take a torch</li></ol>), html
  end

  test "bullet dots and horizontal rules" do
    assert_match "<ul><li>one</li><li>two</li></ul>", render("• one\n• two")
    assert_match "<hr>", render("above\n\n---\n\nbelow")
  end

  test "plain drops the markers for a preview" do
    text = "## The first hour\n**Search** the house\n| Who | Why |\n|---|---|\n| Vet | Chip |\n- a [link](https://x.test)"

    assert_equal "The first hour\nSearch the house\nWho · Why\nVet · Chip\n• a link", Markdown.plain(text)
  end
end
