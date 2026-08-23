# Rendering for the chat surface (D29).
#
# Assistant turns arrive as plain conversational text — the chat tools ask
# for exactly that — but every model still reaches for a little markdown:
# a **bold** phrase, a dashed list, numbered steps, a bare URL. Printing
# the asterisks verbatim is the loudest tell that a chat surface is
# homemade, so the transcript renders a deliberately tiny subset:
# paragraphs, bullet and numbered lists, short headings, bold, italic,
# inline code, and links.
#
# Safety is structural, not careful: every line is HTML-escaped *first*,
# and the inline pass only ever runs over already-escaped text, inserting
# tags this file wrote. Nothing a model emits can become markup.
module ChatHelper
  BULLET = /\A[-*•]\s+(.+)\z/
  NUMBERED = /\A\d{1,3}[.)]\s+(.+)\z/
  HEADING = /\A\#{1,6}\s+(.+?)\s*\#*\z/
  # A fence opens on ``` (with an optional language tag we ignore) and closes
  # on the next one — or, if the model never closed it, at the end of the turn.
  FENCE = /\A```/
  # Code spans and URLs are lifted out whole so the emphasis pass can't
  # chew on an underscore inside either one.
  PROTECTED = %r{(`[^`\n]+`|https?://[^\s<]+)}
  TRAILING_PUNCTUATION = /[.,;:!?)\]]+\z/

  def chat_body(text)
    lines = text.to_s.gsub("\r\n", "\n").split("\n")
    blocks = []
    index = 0

    while index < lines.length
      line = lines[index].strip

      if line.empty?
        index += 1
      elsif line.match?(FENCE)
        # Inside a fence, nothing is markup and nothing is a list: the lines
        # go through verbatim (escaped), keeping their own leading whitespace,
        # because indentation is the meaning. A `tutor` asked anything
        # technical reaches for a fence, and printing the backticks was the
        # loudest remaining tell that this surface was homemade.
        index += 1
        body = []
        while index < lines.length && !lines[index].match?(FENCE)
          body << lines[index]
          index += 1
        end
        index += 1 if index < lines.length # the closing fence, if there is one
        blocks << chat_code_block(body)
      elsif (kind = chat_list_kind(line))
        items = []
        while index < lines.length && chat_list_kind(lines[index].strip) == kind
          items << chat_list_item(lines[index].strip)
          index += 1
        end
        blocks << chat_list(kind, items)
      elsif (heading = line[HEADING, 1])
        blocks << tag.p(chat_inline(heading), class: "font-semibold")
        index += 1
      else
        paragraph = []
        while index < lines.length && chat_paragraph_line?(lines[index])
          paragraph << lines[index].strip
          index += 1
        end
        blocks << tag.p(chat_inline(paragraph.join("\n")), class: "whitespace-pre-line")
      end
    end

    safe_join(blocks)
  end

  private
    def chat_paragraph_line?(line)
      stripped = line.strip
      stripped.present? && chat_list_kind(stripped).nil? &&
        !stripped.match?(HEADING) && !stripped.match?(FENCE)
    end

    # Escaped, never inlined: a code block is the one place a model's text is
    # shown exactly as written. The `pre` scrolls inside itself (see .bubble
    # pre) so a wide line can't widen the bubble.
    def chat_code_block(body)
      code = ERB::Util.html_escape(body.join("\n")).to_str
      tag.pre(tag.code(code.html_safe))
    end

    def chat_list_kind(line)
      if line.match?(BULLET) then :bullet
      elsif line.match?(NUMBERED) then :numbered
      end
    end

    def chat_list_item(line)
      line[BULLET, 1] || line[NUMBERED, 1]
    end

    def chat_list(kind, items)
      body = safe_join(items.map { |item| tag.li(chat_inline(item)) })

      if kind == :bullet
        tag.ul(body, class: "list-disc space-y-1 pl-5")
      else
        tag.ol(body, class: "list-decimal space-y-1 pl-5")
      end
    end

    def chat_inline(text)
      escaped = ERB::Util.html_escape(text).to_str

      escaped.split(PROTECTED).map { |part| chat_inline_part(part) }.join.html_safe
    end

    def chat_inline_part(part)
      if part.start_with?("`") && part.end_with?("`") && part.length > 2
        tag.code(part[1..-2].html_safe, class: "rounded bg-black/5 px-1 py-0.5 font-mono text-[0.85em]").to_str
      elsif part.start_with?("http://", "https://")
        chat_link(part)
      else
        chat_emphasis(part)
      end
    end

    # A sentence-final URL keeps its punctuation out of the href. The anchor
    # is assembled by hand rather than through tag(): `href` is already
    # HTML-escaped, so quotes can't break the attribute and `&amp;` is the
    # encoding an href wants — running it through tag() would escape it twice.
    def chat_link(url)
      trailing = url[TRAILING_PUNCTUATION] || ""
      href = url.delete_suffix(trailing)

      %(<a href="#{href}" target="_blank" rel="noopener noreferrer" ) +
        %(class="underline underline-offset-2 hover:opacity-80">#{href}</a>#{trailing})
    end

    def chat_emphasis(part)
      part
        .gsub(/\*\*(?=\S)(.+?)(?<=\S)\*\*/) { tag.strong($1.html_safe).to_str }
        .gsub(/(?<![\w*_])[*_](?=\S)([^*_\n]+?)(?<=\S)[*_](?![\w*_])/) { tag.em($1.html_safe).to_str }
    end
end
