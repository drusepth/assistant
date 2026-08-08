module Career
  # The win log (D30): one-line accomplishment Notes wearing a "Win:" title
  # prefix, quick-captured from the Career page. The payoff comes later —
  # the raise case, resume tailoring, and interview prep all build from
  # these receipts instead of the user's memory the night before a review.
  module WinLog
    TITLE_PREFIX = "Win:".freeze

    module_function

    def log!(user:, text:)
      text = text.to_s.squish
      raise ArgumentError, "a win needs a line" if text.blank?

      note = user.notes.create!(title: "#{TITLE_PREFIX} #{text.truncate(80)}", body: text)
      note.sections = Section.where(slug: "career")
      note
    end

    def scope(user)
      user.notes.where("title LIKE ?", "#{TITLE_PREFIX}%")
    end
  end
end
