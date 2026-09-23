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
      # section row: Money covers its seven subsections, Health and Pets
      # both cover the pet tools, and the two cross-cutting hubs cover no section at all.
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
      entry("why", "Why we built this",
        "Help you own, instead of help you rent."),
      entry("privacy", "Private by design",
        "Nothing leaves your network. Here is exactly what that means."),
      entry("models", "The model, explained",
        "What actually does the thinking, and what it needs from your computer."),
      entry("install", "Getting started",
        "What it takes to have this running tonight."),
      entry("household", "Your household",
        "Several people, one machine, private from each other by default."),
      entry("faq", "Questions",
        "The ones worth asking before you install anything."),
      entry("open-source", "Open source",
        "Read every line, change what you like, and keep it if we disappear.")
    ].freeze

    # The eleven hubs. Nine are the app's sections; `your-day` and
    # `your-stuff` exist because much of what is built lives across all of
    # them and would otherwise have no page to live on.
    HUBS = [
      entry("your-day", "Your day",
        "The calendar, the tasks, the dashboard — useful before any model is configured."),
      entry("your-stuff", "Your stuff",
        "Documents, photos, recipes, email, passwords, the diary."),
      entry("health", "Health",
        "Appointments, results, insurance, and the care everyone in the house needs.",
        sections: %w[ health ],
        featured: %w[ results_explainer doctor_visit_prep insurance_explainer
                      insurance_appeal find_care compare_plans ]),
      entry("money", "Money",
        "Where it goes, what you owe, and what you're entitled to.",
        sections: %w[ money budget debt taxes assets bills subscriptions benefits ],
        featured: %w[ build_my_budget spending_review debt_payoff_plan
                      benefits_screener cancel_subscription money_coach ]),
      entry("career", "Career",
        "Finding work, being paid properly, and the conversations in between.",
        sections: %w[ career ],
        featured: %w[ interview_prep mock_interview tailor_application
                      negotiation_prep check_pay_stub wage_claim ]),
      entry("education", "Education",
        "A personal school for whoever is learning — including you.",
        sections: %w[ education ]),
      entry("people", "People",
        "The ones you'd regret losing touch with.",
        sections: %w[ people ],
        featured: %w[ reconnect get_together what_do_i_say gift_ideas
                      make_new_friends bereavement ]),
      entry("hobbies", "Hobbies",
        "Your own reading, your own making, and the people who share it.",
        sections: %w[ hobbies ]),
      entry("rights", "Rights",
        "The letters people otherwise pay a lawyer to write.",
        sections: %w[ rights immigration renting voting disputes ],
        featured: %w[ decode_letter deposit_demand dispute_letter
                      debt_collector_response wage_claim accommodation_request ]),
      entry("travel", "Travel",
        "Where you've been, drawn from your own photos, and where you're going.",
        sections: %w[ travel ]),
      entry("pets", "Pets",
        "The dependents who can't tell you what hurts, or when the food runs out.",
        sections: %w[ pets ],
        featured: %w[ pet_care vet_visit_prep decode_vet_estimate
                      compare_pet_insurance new_pet lost_pet ])
    ].freeze

    # One page per substantial feature, each declaring the hub it hangs
    # under. Adding one is a new row here plus a new partial — see
    # docs/ABOUT_PLAN.md §9 on why they are separate files.
    Feature = Data.define(:slug, :hub, :title, :blurb) do
      def to_param = slug
    end

    def self.feature(slug, hub, title, blurb) = Feature.new(slug:, hub:, title:, blurb:)

    FEATURES = [
      feature("dashboard", "your-day", "The dashboard",
        "What needs attention this week, read across every part of your life at once."),
      feature("calendar", "your-day", "Calendar",
        "One calendar for a whole life, not a work one with the rest bolted on."),
      feature("tasks", "your-day", "Tasks and goals",
        "Day-sized things on a board, and big ambitions broken down into them."),
      feature("notes", "your-day", "Notes",
        "What you know, kept where the rest of your life can reach it."),
      feature("chat", "your-day", "Chat",
        "For when a form is the wrong shape — and it has already read your files."),

      feature("documents", "your-stuff", "Documents",
        "Files with their text pulled out, summarised in plain language, and findable."),
      feature("photos", "your-stuff", "Photos",
        "The family library on your own storage, with albums you choose to share."),
      feature("recipes", "your-stuff", "Recipes",
        "A recipe box that scales a batch and shares a book, without the 900-word memoir."),
      feature("email", "your-stuff", "Email",
        "Your mail mirrored onto your own disk, so the app can notice the deadline in it."),
      feature("passwords", "your-stuff", "Passwords",
        "A household vault, encrypted so that a stolen disk is worth nothing."),
      feature("diary", "your-stuff", "Diary",
        "A sealed journal: everything but the date encrypted, and no sharing at all."),

      feature("care-radar", "health", "The care radar",
        "What's quietly gone too long — for everyone in the house, including the pets."),
      feature("insurance", "health", "Insurance",
        "Your plan in plain language, and the appeal for when they say no."),
      feature("pets", "pets", "Pets",
        "The dependent who can't tell you what hurts, given a record and a reorder date."),

      feature("budget", "money", "Budget",
        "Categories you set, spending measured against them, no bank login anywhere."),
      feature("spending", "money", "The spending ledger",
        "Where it actually went, taught once and sorted from then on."),
      feature("debt", "money", "Debt",
        "Every debt in one place, with the interest written down and an order to kill them in."),
      feature("benefits", "money", "Benefits",
        "A screen for the money you're entitled to and nobody told you about."),

      feature("job-search", "career", "The job search",
        "A paced search, and applications written from your real history."),
      feature("interviews", "career", "Interviews",
        "Preparation from the listing, and practice out loud with someone who remembers."),
      feature("pay", "career", "Pay and raises",
        "Your stub explained, your wins logged, and the case built from both."),

      feature("curriculum", "education", "The curriculum",
        "Every subject as a map of topics, per learner, with mastery you have to earn."),
      feature("review", "education", "Review",
        "Spaced repetition, so what was learned in March survives to September."),
      feature("records", "education", "Learning records",
        "Portfolios, hours logs and transcripts, generated from the year you already recorded."),

      feature("circles", "people", "Circles",
        "The people you'd regret losing, and the groups real social life actually happens in."),

      feature("reader", "hobbies", "The reader",
        "Your feeds, chronologically, with no ranking and nothing leaving the box."),
      feature("event-radar", "hobbies", "The event radar",
        "What's on near the places you care about, judged against your hobbies — from calendars you chose, never a search."),

      feature("world-map", "travel", "The world map",
        "Everywhere you've been, drawn from your own photos, fetching nothing."),
      feature("trips", "travel", "Trips",
        "Booked or only discussed, where you'll be in March, and somewhere to sleep between."),

      feature("letters", "rights", "The letters",
        "The formal letter, the deadline on your calendar, and no invented statutes.")
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
