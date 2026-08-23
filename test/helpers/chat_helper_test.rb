require "test_helper"

class ChatHelperTest < ActionView::TestCase
  include ChatHelper

  test "paragraphs keep their single line breaks and separate on blank lines" do
    html = chat_body("one\ntwo\n\nthree")

    assert_equal 2, html.scan("<p").length
    assert_match %r{<p class="whitespace-pre-line">one\ntwo</p>}, html
  end

  test "bullet and numbered runs become lists" do
    html = chat_body("Options:\n- first\n* second\n\n1. step one\n2) step two")

    assert_select_fragment html, "ul.list-disc li", count: 2
    assert_select_fragment html, "ol.list-decimal li", count: 2
  end

  test "headings render as their own emphasized line" do
    assert_match %r{<p class="font-semibold">Where we landed</p>}, chat_body("### Where we landed ###")
  end

  test "bold, italic, and inline code render as markup" do
    html = chat_body("**bold** and _soft_ and `code()`")

    assert_match "<strong>bold</strong>", html
    assert_match "<em>soft</em>", html
    assert_match ">code()</code>", html
  end

  test "arithmetic and snake_case are not mistaken for emphasis" do
    html = chat_body("2 * 3 = 6 and due_on * 2 and a lone _")

    assert_no_match "<em>", html
    assert_no_match "<strong>", html
  end

  test "emphasis markers inside code spans are left alone" do
    assert_match ">a_b_c</code>", chat_body("`a_b_c`")
  end

  test "urls link out, leaving sentence punctuation behind" do
    html = chat_body("See https://example.com/a?b=1&c=2.")

    assert_match 'href="https://example.com/a?b=1&amp;c=2"', html
    assert_match 'rel="noopener noreferrer"', html
    assert_match "</a>.", html
  end

  test "model output can never become markup" do
    html = chat_body(%(<script>alert(1)</script> and <img src=x onerror=y> and "quotes"))

    assert_no_match "<script", html
    assert_no_match "<img", html
    assert_match "&lt;script&gt;", html
  end

  test "an html-ish url cannot break out of its own href" do
    html = chat_body(%(https://example.com/"onmouseover="alert(1)))

    assert_no_match "onmouseover=\"", html
    assert_match "&quot;", html
  end

  test "a fenced block renders as code, not as backticks" do
    html = chat_body("Try this:\n```ruby\nputs 1\n```\nMake sense?")

    assert_no_match "```", html
    assert_select_fragment html, "pre code", text: "puts 1"
    assert_select_fragment html, "p", count: 2
  end

  test "a code block keeps its indentation and its markdown-ish characters" do
    html = chat_body("```\n  if x_y **z**\n    return\n```")

    assert_match "  if x_y **z**\n    return", html
    assert_no_match "<em>", html
    assert_no_match "<strong>", html
  end

  test "a code block is escaped like everything else" do
    html = chat_body("```\n<script>alert(1)</script>\n```")

    assert_no_match "<script", html
    assert_match "&lt;script&gt;", html
  end

  test "an unclosed fence takes the rest of the turn rather than dropping it" do
    html = chat_body("Here:\n```\nputs 1\nputs 2")

    assert_match "puts 1\nputs 2", html
    assert_select_fragment html, "pre code", count: 1
  end

  private
    def assert_select_fragment(html, selector, **options)
      assert_select Nokogiri::HTML5.fragment(html), selector, **options
    end
end
