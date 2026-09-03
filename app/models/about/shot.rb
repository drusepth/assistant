module About
  # The screenshot registry (docs/ABOUT_PLAN.md §7).
  #
  # One list, read by two things that must never disagree: the capture run
  # (`bin/rails screenshots:capture`, which drives a real browser over the
  # demo household and writes the files) and the /about views (which render
  # them). A shot the views ask for but the capture doesn't take would be a
  # broken image on a public page; a shot the capture takes but nothing
  # renders is dead weight in the repository. `AboutShotsTest` pins both
  # directions.
  #
  # Shots are captured signed in as the demo household's admin, so every
  # image is of the fictional Okafor–Lynch family (db/demo.rb) and never of
  # anybody real.
  module Shot
    Entry = Data.define(:name, :path, :caption, :height, :as) do
      # The asset the views reference and the capture writes. WEBP because
      # these are screenshots of flat UI, where it beats PNG by roughly
      # four to one at a quality nobody can see.
      def filename = "about/#{name}.webp"

      # The signed-in user the shot is taken as. Kay sees the most (she is
      # the admin and the household's organiser); Ify's pages are the only
      # ones that need a different login.
      def user = as || "kay@example.com"

      # Full-page shots run long and read as a wall of nothing at page
      # width, so most shots are cropped to the top of the page — the part
      # that actually makes the argument.
      def full_page? = height.nil?
    end

    def self.entry(name, path, caption, height: 900, as: nil)
      Entry.new(name:, path:, caption:, height:, as:)
    end

    LIST = [
      entry("dashboard", "/",
        "The dashboard, reading across every part of one household's week."),
      entry("calendar", "/calendar",
        "One calendar: the cardiology appointment, the rent, and the interview."),
      entry("today", "/today",
        "Today — what's due, what's coming, and what quietly slipped."),
      entry("tasks", "/tasks",
        "The board, with a goal's steps filed among the ordinary jobs."),
      entry("money", "/sections/money",
        "The Money section: spent against planned, with no bank connected."),
      entry("spending", "/spending",
        "The ledger, sorted by rules the household taught it once."),
      entry("health", "/sections/health",
        "Health: what's due, what's booked, and everyone it covers."),
      entry("career", "/sections/career",
        "Career, in the middle of a layoff it did not cause."),
      entry("rights", "/sections/rights",
        "Rights: a collections letter with a window that is still open."),
      entry("education", "/sections/education",
        "A learner's own subjects, and what they have actually mastered.",
        as: "ify@example.com"),
      entry("people", "/people",
        "The circle — the people you'd regret losing touch with."),
      entry("photos", "/photos",
        "The family library, on the household's own storage."),
      entry("world_map", "/photos/map",
        "Everywhere they have been, drawn from their own photographs."),
      entry("reader", "/reader",
        "The reader: chosen sources, newest first, nothing reordered."),
      entry("recipes", "/recipes",
        "The recipe box, including the ones written down before they were lost."),
      entry("documents", "/documents",
        "The vault: files with their text pulled out and summarised."),
      entry("passwords", "/credentials",
        "The password vault, sealed with a key derived from a login password."),
      entry("trips", "/trips",
        "Trips: what is booked, and what everybody only talked about.")
    ].freeze

    def self.find(name) = LIST.find { |shot| shot.name == name.to_s }

    def self.names = LIST.map(&:name)

    # Where the capture writes and the asset pipeline reads.
    def self.directory = Rails.root.join("app/assets/images/about")
  end
end
