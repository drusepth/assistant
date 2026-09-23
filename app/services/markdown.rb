# The slice of Markdown the app's long-form text actually uses, rendered
# safely: a diary entry someone typed, and every draft a tool writes (the
# draft tools ask for Markdown outright — see Tool::Base::DRAFT_FORMAT — and a
# model reaches for it even when not asked).
#
# Written here rather than pulled in as a gem for two reasons. The obvious
# one is the project's one-command-install principle: a general Markdown
# engine is a large dependency to carry for headings and bold. The better
# one is that a general engine's job includes passing raw HTML through,
# which is precisely the behaviour a page rendering someone's private
# writing — or a model's output — must not have, and turning it off
# correctly is more subtle than the file below.
#
# The safety argument is short enough to check by reading: **everything is
# HTML-escaped before a single rule runs**, so no markup a writer or a model
# types can survive into the output. The only tags on the page are the ones
# this file writes itself — through `wrap`, `line_break`, the table and
# numbered-list openers, and the single `a` in `links` — and the only
# attributes any of them carry are an href that had to match ALLOWED_URL
# first, a `start` that is digits, a constant class, and a `data-label`
# built from already-escaped text.
module Markdown
  # Only schemes that can't execute. Everything else — javascript:, data:,
  # vbscript:, a scheme-relative //host — renders as plain text.
  ALLOWED_URL = %r{\Ahttps?://[^\s"'<>]+\z}i

  FENCE = /\A\s*```/
  HEADING = /\A\s*(\#{1,6})\s+(.*?)\s*\#*\s*\z/
  # `&gt;`, not `>`: these patterns run *after* escaping, which is the whole
  # basis of the safety argument above — so the one marker HTML-escaping
  # touches has to be matched in its escaped form.
  QUOTE = /\A\s*&gt;\s?(.*)\z/
  # A model writes "•" as often as "-", and indents a sub-point under its
  # parent; both are lists.
  BULLET = /\A(\s*)[-*+•]\s+(.*)\z/
  NUMBERED = /\A(\s*)(\d{1,3})[.)]\s+(.*)\z/
  RULE = /\A\s*([-*_])(\s*\1){2,}\s*\z/
  TABLE_ROW = /\A\s*\|/
  TABLE_DIVIDER = /\A\s*:?-{2,}:?\s*\z/
  # A model breaks a line inside a table cell the only way a cell allows —
  # with a literal <br> — and escaping has already turned it into text.
  CELL_BREAK = %r{&lt;br\s*/?&gt;}i

  # Headings inside a body are section markers in a page that already has a
  # title, so they start below it rather than competing with it.
  HEADING_TAGS = { 1 => "h2", 2 => "h3" }.freeze

  module_function

  def render(text)
    blocks(escape(text)).join("\n").html_safe # rubocop:disable Rails/OutputSafety
  end

  # The same text with its markers dropped — for a line-clamped preview,
  # where a heading or a table has no room to be one. Plain text, so the view
  # escapes it as usual.
  def plain(text)
    text.to_s.gsub("\r\n", "\n").split("\n").filter_map do |line|
      next if line.match?(FENCE) || table_divider?(line) || line.match?(RULE)

      line = line.sub(BULLET) { "• #{Regexp.last_match(2)}" }
      line = line.strip.delete_prefix("|").delete_suffix("|").split("|").map(&:strip).join(" · ") if line.match?(TABLE_ROW)
      line.gsub(/\A\s*\#{1,6}\s+|\*\*|__|`|\A\s*>\s?/, "").gsub(/\[([^\]]+)\]\([^)]*\)/, '\1').strip.presence
    end.join("\n")
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
      when TABLE_ROW then out << table(lines)
      when RULE then out << (lines.shift && "<hr>")
      when QUOTE then out << wrap("blockquote", gather(lines, QUOTE).map { |l| inline(l) }.join(line_break))
      when BULLET, NUMBERED then out << list(lines)
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
    wrap(HEADING_TAGS.fetch(level.length, "h4"), inline(text))
  end

  # A run of list lines. The list's kind is its first line's; a line
  # indented past that one is a sub-point of the item above it, and an
  # indented line with no marker at all is that item wrapping onto a second
  # line — both shapes a model writes constantly. One level of nesting is
  # all a draft needs; deeper indents join the sub-list.
  #
  # A numbered list keeps its first number, so steps a model separated with
  # blank lines ("1.", blank, "2.") still count 1, 2 rather than 1, 1.
  def list(lines)
    first = list_marker(lines.first)
    items = []

    while (line = lines.first)
      marker = list_marker(line)

      if marker && marker[:indent] <= first[:indent]
        break unless marker[:tag] == first[:tag]

        items << { text: [ marker[:text] ], children: [] }
      elsif marker
        items.last[:children] << marker[:text]
      elsif line.match?(/\A\s+\S/) && !block_start?(line)
        target = items.last[:children].any? ? items.last[:children] : items.last[:text]
        target[-1] = "#{target[-1]}\n#{line.strip}"
      else
        break
      end
      lines.shift
    end

    body = items.map do |item|
      text = item[:text].map { |t| inline_lines(t) }.join
      text += wrap("ul", item[:children].map { |child| wrap("li", inline_lines(child)) }.join) if item[:children].any?
      wrap("li", text)
    end.join

    start = first[:number].to_i
    first[:tag] == "ol" && start > 1 ? %(<ol start="#{start}">#{body}</ol>) : wrap(first[:tag], body)
  end

  def list_marker(line)
    if (match = line.match(BULLET))
      { tag: "ul", indent: match[1].length, text: match[2] }
    elsif (match = line.match(NUMBERED))
      { tag: "ol", indent: match[1].length, text: match[3], number: match[2] }
    end
  end

  # A table in the shape models write: pipe-delimited rows, usually with a
  # `|---|` divider under the header. Models also break a row across lines
  # when a cell holds a list, so a row that doesn't end in a pipe keeps
  # taking the lines under it until one does. A cell whose lines are all
  # bullets becomes a list; any other multi-line cell keeps its breaks.
  #
  # Each cell carries its column's header as `data-label`, which is how the
  # stylesheet turns a table into stacked cards on a phone instead of a grid
  # that has to scroll sideways.
  def table(lines)
    rows = []

    while lines.first&.match?(TABLE_ROW)
      row = lines.shift.strip
      until row.end_with?("|") || lines.empty? || lines.first.match?(/\A\s*\z/) || lines.first.match?(TABLE_ROW)
        row += "\n#{lines.shift.strip}"
      end
      rows << cells(row)
    end

    header = rows[1] && rows[1].all? { |cell| cell.match?(TABLE_DIVIDER) } ? rows.shift.tap { rows.shift } : nil
    rows.reject! { |row| row.all? { |cell| cell.match?(TABLE_DIVIDER) } }
    labels = Array(header).map { |cell| cell.gsub(/[*`]|__|\n/, " ").squish }

    head = header ? wrap("thead", wrap("tr", header.map { |cell| wrap("th", inline_lines(cell)) }.join)) : ""
    body = rows.map do |row|
      wrap("tr", row.each_with_index.map do |cell, index|
        label = labels[index]
        open = label.present? ? %(<td data-label="#{label}">) : "<td>"
        "#{open}#{cell_body(cell)}</td>"
      end.join)
    end.join

    %(<div class="prose-table">#{wrap("table", head + wrap("tbody", body))}</div>)
  end

  def cells(row)
    row.delete_prefix("|").delete_suffix("|").split("|").map { |cell| cell.gsub(CELL_BREAK, "\n").strip }
  end

  def cell_body(cell)
    lines = cell.split("\n").map(&:strip).reject(&:empty?)
    if lines.length > 1 && lines.all? { |line| line.match?(BULLET) }
      wrap("ul", lines.map { |line| wrap("li", inline(line.match(BULLET)[2])) }.join)
    else
      lines.map { |line| inline(line) }.join(line_break)
    end
  end

  def table_divider?(line)
    line.match?(TABLE_ROW) && line.strip.delete_prefix("|").delete_suffix("|").split("|").all? { |cell| cell.match?(TABLE_DIVIDER) }
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
    body << lines.shift until lines.empty? || lines.first.match?(/\A\s*\z/) || block_start?(lines.first)

    wrap("p", body.map { |line| inline(line.strip) }.join(line_break))
  end

  def block_start?(line)
    [ FENCE, HEADING, TABLE_ROW, RULE, QUOTE, BULLET, NUMBERED ].any? { |pattern| line.match?(pattern) }
  end

  def inline_lines(text) = text.split("\n").map { |line| inline(line) }.join(line_break)

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
  # renders as text — not worth a clever URL parser.
  def links(text)
    text.gsub(/\[([^\]]+)\]\(([^)\s]+)\)/) do
      label, url = Regexp.last_match(1), Regexp.last_match(2)
      next Regexp.last_match(0) unless url.match?(ALLOWED_URL)

      %(<a href="#{url}" rel="noopener noreferrer nofollow" target="_blank">#{label}</a>)
    end
  end

  def line_break = "<br>"

  def wrap(tag, inner) = "<#{tag}>#{inner}</#{tag}>"
end
