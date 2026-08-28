module About
  # The registry behind every /about URL (D-about-pages).
  #
  # Two jobs. The first is navigational: the hubs and features listed here
  # are what the index renders and what each hub links down into. The second
  # is a security boundary — a slug reaches a template only by matching an
  # entry in one of these lists, so no request can interpolate itself into a
  # template lookup. An unknown slug is a 404, not a render.
  #
  # Nothing here reads the database. These pages are byte-identical on every
  # install, which is what makes the tree safe to expose at all: it
  # describes the software, never the household.
  module Page
    Entry = Data.define(:slug, :title, :blurb, :sections, :featured) do
      def to_param = slug

      # The tools this page speaks for. Declared here rather than read from
      # the section taxonomy because a hub does not map cleanly onto one
      # section row: Money covers its seven subsections, Health covers the
      # pet tools, and the two cross-cutting hubs cover no section at all.
      def tools
        return [] if sections.empty?

        Tool.all.select { |tool| tool.section_slugs.intersect?(sections) }
      end

      # The tools this hub leads with. Tools register on several sections,
      # so the full list runs long and dilutes — Money's sixteen include "I
      # lost my job", which belongs to it and yet is not what Money *is*.
      # A hub with a curated list shows it and links to the rest; one
      # without shows everything, which is the right default until a hub's
      # buildout wave decides otherwise.
      def featured_tools = featured.map { |slug| Tool.find!(slug) }
    end

    def self.entry(slug, title, blurb, sections: [], featured: [])
      Entry.new(slug:, title:, blurb:, sections:, featured:)
    end

    # The top-level pages — the "why should I run this" half of the site.
    # Order is the order they appear in the footer and on the index.
    #
    # Unlike a hub, one of these is nothing but its prose, so an entry here
    # without a partial is a dead link rather than a thin page. A page is
    # therefore registered in the same commit that writes it (see
    # docs/ABOUT_PLAN.md §8 — `why`, `models`, `install`, `household`,
    # `faq` and `open-source` arrive in wave 2), and
    # `About::PagesTest#test_every_registered_page_renders` holds the line.
    TOP_LEVEL = [
      entry("privacy", "Private by design",
        "Nothing leaves your network. Here is exactly what that means.")
    ].freeze

    # The ten hubs. Eight are the app's sections; `your-day` and
    # `your-stuff` exist because much of what is built lives across all of
    # them and would otherwise have no page to live on.
    HUBS = [
      entry("your-day", "Your day",
        "The calendar, the tasks, the dashboard — useful before any model is configured."),
      entry("your-stuff", "Your stuff",
        "Documents, photos, recipes, email, passwords, the diary."),
      entry("health", "Health",
        "Appointments, results, insurance, and the care everyone in the house needs.",
        sections: %w[ health ]),
      entry("money", "Money",
        "Where it goes, what you owe, and what you're entitled to.",
        sections: %w[ money budget debt taxes assets bills subscriptions benefits ],
        featured: %w[ build_my_budget spending_review debt_payoff_plan
                      benefits_screener cancel_subscription money_coach ]),
      entry("career", "Career",
        "Finding work, being paid properly, and the conversations in between.",
        sections: %w[ career ]),
      entry("education", "Education",
        "A personal school for whoever is learning — including you.",
        sections: %w[ education ]),
      entry("people", "People",
        "The ones you'd regret losing touch with.",
        sections: %w[ people ]),
      entry("hobbies", "Hobbies",
        "Your own reading, your own making, and the people who share it.",
        sections: %w[ hobbies ]),
      entry("rights", "Rights",
        "The letters people otherwise pay a lawyer to write.",
        sections: %w[ rights immigration renting voting disputes ]),
      entry("travel", "Travel",
        "Where you've been, drawn from your own photos, and where you're going.",
        sections: %w[ travel ])
    ].freeze

    # One page per substantial feature, each declaring the hub it hangs
    # under. Adding one is a new row here plus a new partial — see
    # docs/ABOUT_PLAN.md §9 on why they are separate files.
    Feature = Data.define(:slug, :hub, :title, :blurb) do
      def to_param = slug
    end

    def self.feature(slug, hub, title, blurb) = Feature.new(slug:, hub:, title:, blurb:)

    FEATURES = [
      feature("budget", "money", "Budget",
        "Categories you set, spending measured against them, no bank login anywhere.")
    ].freeze

    module_function

    def top_level(slug) = TOP_LEVEL.find { |page| page.slug == slug }
    def hub(slug) = HUBS.find { |page| page.slug == slug }
    def feature(slug) = FEATURES.find { |page| page.slug == slug }

    # The features hanging under one hub — what a hub page's "read more"
    # block lists.
    def features_for(hub_slug) = FEATURES.select { |page| page.hub == hub_slug }

    # Every path in the tree, for the sitemap and for the test that pins
    # each registered page to a template that actually exists.
    def all_slugs = TOP_LEVEL.map(&:slug) + HUBS.map(&:slug) + FEATURES.map(&:slug)
  end
end
