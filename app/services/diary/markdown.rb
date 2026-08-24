module Diary
  # The small slice of Markdown a diary actually uses, rendered safely.
  #
  # Written here rather than pulled in as a gem for two reasons. The obvious
  # one is the project's one-command-install principle: a general Markdown
  # engine is a large dependency to carry for headings and bold. The better
  # one is that a general engine's job includes passing raw HTML through,
  # which is precisely the behaviour a page rendering someone's private
  # writing must not have — and turning it off correctly is more subtle than
  # the ~100 lines below.
  #
  # The safety argument is short enough to check by reading: **everything is
  # HTML-escaped before a single rule runs**, so no markup a writer types can
  # survive into the output. The only tags on the page are the ones this file
  # writes itself — every one of them through `wrap`, plus the single `a` in
  # `links` — and the only attribute any of them carries is an href that had
  # to match ALLOWED_URL first.
  module Markdown
    # Only schemes that can't execute. Everything else — javascript:, data:,
    # vbscript:, a scheme-relative //host — renders as plain text.
    ALLOWED_URL = %r{\Ahttps?://[^\s"'<>]+\z}i

    FENCE = /\A```/
    HEADING = /\A(\#{1,3})\s+(.*)\z/
    # `&gt;`, not `>`: these patterns run *after* escaping, which is the whole
    # basis of the safety argument above — so the one marker HTML-escaping
    # touches has to be matched in its escaped form.
    QUOTE = /\A&gt;\s?(.*)\z/
    BULLET = /\A[-*]\s+(.*)\z/
    NUMBERED = /\A\d+\.\s+(.*)\z/

    # Headings inside an entry are section markers in a page that already has
    # a title, so they start below it rather than competing with it.
    HEADING_TAGS = { 1 => "h2", 2 => "h3", 3 => "h4" }.freeze

    module_function

    def render(text)
      blocks(escape(text)).join("\n").html_safe # rubocop:disable Rails/OutputSafety
    end

    # The one call that makes everything after it safe.
    def escape(text) = ERB::Util.html_escape(text.to_s.gsub("\r\n", "\n")).to_str

    def blocks(escaped)
      lines = escaped.split("\n")
      out = []

      until lines.empty?
        line = lines.first

        case line
        when FENCE then out << code_block(lines)
        when /\A\s*\z/ then lines.shift
        when HEADING then out << heading(lines.shift)
        when QUOTE then out << wrap("blockquote", gather(lines, QUOTE).map { |l| inline(l) }.join("<br>"))
        when BULLET then out << list("ul", gather(lines, BULLET))
        when NUMBERED then out << list("ol", gather(lines, NUMBERED))
        else out << paragraph(lines)
        end
      end

      out
    end

    # Consecutive lines matching one pattern, with the marker stripped.
    def gather(lines, pattern)
      taken = []
      taken << lines.shift.match(pattern)[1] while lines.first&.match?(pattern)
      taken
    end

    def heading(line)
      level, text = line.match(HEADING).captures
      wrap(HEADING_TAGS.fetch(level.length), inline(text))
    end

    def list(tag, items)
      wrap(tag, items.map { |item| wrap("li", inline(item)) }.join)
    end

    # A fenced block is the one place inline rules must not run: its whole
    # point is that the characters mean themselves.
    def code_block(lines)
      lines.shift
      body = []
      body << lines.shift until lines.empty? || lines.first.match?(FENCE)
      lines.shift # closing fence, if the writer got that far

      wrap("pre", wrap("code", body.join("\n")))
    end

    # Single newlines inside a paragraph are line breaks, because that is
    # what someone typing into a textarea means by them.
    def paragraph(lines)
      body = []
      body << lines.shift until lines.empty? || lines.first.match?(/\A\s*\z/) ||
        lines.first.match?(FENCE) || lines.first.match?(HEADING) ||
        lines.first.match?(QUOTE) || lines.first.match?(BULLET) || lines.first.match?(NUMBERED)

      wrap("p", body.map { |line| inline(line) }.join("<br>"))
    end

    # Code spans are lifted out first so that a `**` inside one stays a pair
    # of asterisks, then put back after the other rules have run.
    #
    # The placeholder is `<n>`, which cannot collide with anything: the text
    # was escaped, so it holds no `<` of its own, and the tags this file adds
    # in between never have a bare number for a name.
    def inline(text)
      spans = []
      text = text.gsub(/`([^`]+)`/) do
        spans << Regexp.last_match(1)
        "<#{spans.length - 1}>"
      end

      text = links(text)
      text = text.gsub(/\*\*(.+?)\*\*/) { wrap("strong", Regexp.last_match(1)) }
      text = text.gsub(/(?<![\w*])\*(?!\s)([^*]+?)(?<!\s)\*(?![\w*])/) { wrap("em", Regexp.last_match(1)) }
      text = text.gsub(/(?<![\w_])_(?!\s)([^_]+?)(?<!\s)_(?![\w_])/) { wrap("em", Regexp.last_match(1)) }

      text.gsub(/<(\d+)>/) { wrap("code", spans[Regexp.last_match(1).to_i]) }
    end

    # A link whose target isn't plainly http(s) keeps its Markdown source and
    # renders as text — a diary is not worth a clever URL parser.
    def links(text)
      text.gsub(/\[([^\]]+)\]\(([^)\s]+)\)/) do
        label, url = Regexp.last_match(1), Regexp.last_match(2)
        next Regexp.last_match(0) unless url.match?(ALLOWED_URL)

        %(<a href="#{url}" rel="noopener noreferrer nofollow" target="_blank">#{label}</a>)
      end
    end

    def wrap(tag, inner) = "<#{tag}>#{inner}</#{tag}>"
  end
end
