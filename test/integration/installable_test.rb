require "test_helper"

# The web app manifest (CHAT_PLAN.md W5). Installing removes the browser's own
# URL bar and tab strip, which is the largest single pixel win available on a
# phone — and it applies to every page, not just the chat.
class InstallableTest < ActionDispatch::IntegrationTest
  MANIFEST = Rails.root.join("public/manifest.json")
  TOKENS = Rails.root.join("app/assets/tailwind/application.css")

  setup { @manifest = JSON.parse(MANIFEST.read) }

  test "the manifest says everything a browser needs to offer an install" do
    assert_equal "standalone", @manifest["display"]
    assert_equal "/", @manifest["start_url"]
    assert_equal "/", @manifest["scope"]
    assert @manifest["name"].present?
    assert @manifest["short_name"].present?
    assert @manifest["icons"].any?, "an install with no icon is not an install"
  end

  test "every icon it names is actually on disk" do
    @manifest["icons"].each do |icon|
      path = Rails.root.join("public", icon["src"].delete_prefix("/"))
      assert path.exist?, "the manifest points at #{icon["src"]}, which isn't there"
    end
  end

  # A maskable icon is cropped to a circle on Android, so art without a safe
  # area inside it loses its edges. Claiming the purpose before the art is
  # drawn for it is worse than not claiming it — the install just looks broken.
  test "nothing claims to be maskable until an icon is drawn for it" do
    purposes = @manifest["icons"].filter_map { |icon| icon["purpose"] }

    assert_not purposes.any? { |purpose| purpose.split.include?("maskable") },
      "a maskable icon needs art with its own safe area — see CHAT_PLAN.md W5"
  end

  test "the manifest's colours are the app's colours" do
    css = TOKENS.read

    assert_equal css[/--color-canvas:\s*(#\h+)/, 1], @manifest["background_color"],
      "the splash background drifted from --color-canvas"
    assert_equal css[/--color-surface:\s*(#\h+)/, 1], @manifest["theme_color"],
      "the status-bar tint drifted from --color-surface, which the app header uses"
  end

  test "a signed-in page links the manifest and asks for the platform's chrome" do
    sign_in_as users(:one)
    get root_path

    assert_select "link[rel=manifest][href=?]", "/manifest.json"
    assert_select "meta[name=theme-color][content=?]", @manifest["theme_color"]
    assert_select "meta[name='apple-mobile-web-app-status-bar-style']"
  end

  # A share link is one page shown to somebody outside the household. Offering
  # them an install of another person's assistant would be absurd, and the
  # bare layout is also where a stray manifest would be least noticed.
  test "a public share page offers no install of somebody else's assistant" do
    recipe = users(:one).recipes.create!(title: "Grandma's soup")
    link = users(:one).share_links.create!(subject: recipe)

    get shared_path(link.token)

    assert_response :success
    assert_select "link[rel=manifest]", count: 0
    assert_select "meta[name=theme-color]", count: 0
  end
end
