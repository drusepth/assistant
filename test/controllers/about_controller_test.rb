require "test_helper"

# The /about tree (D-about-pages): the app's second unauthenticated read
# path, so the tests that matter most are the ones about who can reach it
# and what it refuses to render.
class AboutControllerTest < ActionDispatch::IntegrationTest
  setup { @household = households(:smith) }

  # --- reachability ---------------------------------------------------

  test "a stranger reads the tree while public pages are on" do
    get about_root_path
    assert_response :success

    get about_page_path("privacy")
    assert_response :success
  end

  test "a stranger gets nothing once the household turns them off" do
    @household.update!(public_pages_enabled: false)

    get about_root_path
    assert_response :not_found
  end

  # A 403 would confirm the tree is there, which is the one thing the switch
  # is hiding.
  test "the refusal is a 404, never a 403" do
    @household.update!(public_pages_enabled: false)

    [ about_root_path, about_page_path("privacy"), about_tools_path,
      about_hub_path("money"), about_tool_path("deposit_demand") ].each do |path|
      get path
      assert_response :not_found, "#{path} should 404 while public pages are off"
    end
  end

  # Turning off the public site must not delete the household's own
  # documentation.
  test "a signed-in member still reads the tree while it is off" do
    @household.update!(public_pages_enabled: false)
    sign_in_as users(:one)

    get about_root_path
    assert_response :success
  end

  # --- the registry as a security boundary ----------------------------

  test "an unregistered slug never reaches a template lookup" do
    [ about_page_path("nope"), about_hub_path("nope"), about_feature_path("nope"),
      about_tool_path("nope") ].each do |path|
      get path
      assert_response :not_found, "#{path} should 404"
    end
  end

  test "a traversal attempt is a 404 rather than a render" do
    get "/about/..%2f..%2fconfig%2fdatabase"
    assert_response :not_found
  end

  # --- what the pages may contain -------------------------------------

  # The claim the whole switch rests on: these pages describe the software,
  # never the household running this copy (D-about-pages).
  test "no page leaks anything about this household" do
    paths = [ about_root_path, about_tools_path, about_page_path("privacy") ] +
      About::Page::HUBS.map { |hub| about_hub_path(hub) } +
      About::Page::FEATURES.map { |feature| about_feature_path(feature) }

    # The fixtures' own values, not a domain heuristic — the test host is
    # www.example.com, so og:url legitimately carries that domain.
    emails = User.pluck(:email_address)

    paths.each do |path|
      get path
      assert_response :success, path
      assert_no_match(/Smith/i, response.body, "#{path} names the household")
      emails.each do |email|
        assert_not_includes response.body, email, "#{path} leaks an email address"
      end
    end
  end

  # --- every registered page renders ----------------------------------

  test "every registered top-level page renders" do
    About::Page::TOP_LEVEL.each do |page|
      get about_page_path(page)
      assert_response :success, "#{page.slug} is registered but does not render"
      assert_select "h1", text: page.title
    end
  end

  test "every registered hub renders" do
    About::Page::HUBS.each do |hub|
      get about_hub_path(hub)
      assert_response :success, "#{hub.slug} is registered but does not render"
      assert_select "h1", text: hub.title
    end
  end

  test "every registered feature renders" do
    About::Page::FEATURES.each do |feature|
      get about_feature_path(feature)
      assert_response :success, "#{feature.slug} is registered but does not render"
      assert_select "h1", text: feature.title
    end
  end

  # A hub backed by sections falls back on generated tool cards, so it is a
  # real page before anyone writes its prose. The two cross-cutting hubs
  # generate nothing, so prose is the only thing they have — registering one
  # without it ships an empty page.
  test "a hub that owns no section has hand-written prose" do
    About::Page::HUBS.select { |hub| hub.sections.empty? }.each do |hub|
      partial = Rails.root.join("app/views/about/sections/_#{hub.slug.tr('-', '_')}.html.erb")
      assert partial.exist?, "#{hub.slug} generates nothing, so it needs #{partial.basename}"
    end
  end

  # --- tools ----------------------------------------------------------

  test "every tool in the registry has a page" do
    Tool::SLUGS.each do |slug|
      get about_tool_path(slug)
      assert_response :success, "#{slug} has no /about page"
      assert_select "h1", text: Tool.find(slug).title
    end
  end

  test "the directory lists every tool" do
    get about_tools_path
    assert_response :success
    Tool::SLUGS.each do |slug|
      assert_select "a[href=?]", about_tool_path(slug), { minimum: 1 },
        "#{slug} is missing from the directory"
    end
  end

  # The invariant behind the directory and the hub cards: every tool is
  # browsable somewhere — from a hub whose sections carry it, or from the
  # directory's contextual block when it registers on no section at all
  # (quiz_note and task_chat start from the note or task itself). What
  # fails here is the third case: a tool registered on a section no hub
  # claims — the fix is a row in that hub's `sections:` list.
  test "every tool is reachable from a hub or the contextual block" do
    orphans = Tool.all.reject do |tool|
      tool.section_slugs.empty? ||
        About::Page::HUBS.any? { |hub| hub.sections.intersect?(tool.section_slugs) }
    end

    assert_empty orphans.map(&:slug),
      "these tools register on sections no hub claims, so no /about page lists them"
  end

  # A featured list is a curation, not a second registry: every slug in it
  # must be a real tool that the hub's own sections already carry.
  test "every featured tool belongs to its hub" do
    About::Page::HUBS.each do |hub|
      hub.featured_tools.each do |tool|
        assert hub.sections.intersect?(tool.section_slugs),
          "#{tool.slug} is featured on #{hub.slug} but registers on none of its sections"
      end
    end
  end

  # The class of bug this tree grows: a page links a slug nobody registered
  # yet. Crawl every page we serve, follow every internal /about link, and
  # let a dead one fail by name.
  test "every internal link on every page resolves" do
    pages = [ about_root_path, about_tools_path ] +
      About::Page::TOP_LEVEL.map { |page| about_page_path(page) } +
      About::Page::HUBS.map { |hub| about_hub_path(hub) } +
      About::Page::FEATURES.map { |feature| about_feature_path(feature) } +
      Tool::SLUGS.map { |slug| about_tool_path(slug) }

    links = pages.each_with_object(Hash.new { |h, k| h[k] = [] }) do |path, found|
      get path
      assert_response :success, path
      response.body.scan(/href="(\/about[^"#?]*)/).flatten.each { |href| found[href] << path }
    end

    links.each do |href, sources|
      get href
      assert_response :success, "dead link #{href} (from #{sources.uniq.first(3).join(', ')})"
    end
  end

  # The pages are the same bytes on every install, so a tool page must not
  # depend on anything a household did.
  test "a tool page renders for a household with no data at all" do
    Household.destroy_all

    get about_tool_path("deposit_demand")
    assert_response :success
  end
end
