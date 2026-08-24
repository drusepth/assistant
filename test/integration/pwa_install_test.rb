require "test_helper"

# The install manifest. A self-hosted app that can be added to a phone's home
# screen is worth more than the same app in a tab — it gets its own window,
# its own icon, and (the reason this was wired up at all) the left screen
# edge back from the browser's own back gesture, which is what lets the nav
# drawer's edge swipe work in full.
#
# All of it is inert unless the manifest is reachable, linked, and complete,
# and every one of those three has failed silently for a year already: the
# file shipped with Rails' scaffold values and no route pointing at it.
class PwaInstallTest < ActionDispatch::IntegrationTest
  test "the manifest is served without signing in" do
    get pwa_manifest_path

    assert_response :success
    assert_nothing_raised { JSON.parse(response.body) }
    assert_equal "application/manifest+json", response.media_type
  end

  test "the manifest carries what a browser needs to offer an install" do
    get pwa_manifest_path
    manifest = JSON.parse(response.body)

    assert_equal "Assistant", manifest["name"]
    assert_equal "standalone", manifest["display"]
    assert_equal "/", manifest["start_url"]
    assert_predicate manifest["short_name"].to_s, :present?
    # Chrome will not offer an install without a 192 and a 512.
    assert_equal [ "192x192", "512x512" ], manifest["icons"].map { |icon| icon["sizes"] }.sort
  end

  test "the manifest icons exist and are the size they claim" do
    require "vips"

    get pwa_manifest_path

    JSON.parse(response.body)["icons"].each do |icon|
      path = Rails.root.join("public", icon["src"].delete_prefix("/"))
      assert path.exist?, "#{icon["src"]} is in the manifest but not in public/"

      # A maskable icon is cropped to a centred circle of 80% diameter, so a
      # square that only *claims* to be maskable loses its corners.
      width, height = icon["sizes"].split("x").map(&:to_i)
      image = Vips::Image.new_from_file(path.to_s)
      assert_equal [ width, height ], [ image.width, image.height ],
        "#{icon["src"]} is #{image.width}×#{image.height}, not the #{icon["sizes"]} it claims"
      assert_equal 3, image.bands,
        "#{icon["src"]} has an alpha channel; a transparent ground renders black on an iOS home screen"
    end
  end

  test "no Rails scaffold placeholders survive in the manifest" do
    get pwa_manifest_path
    manifest = JSON.parse(response.body)

    assert_not_equal "red", manifest["theme_color"]
    assert_not_equal "red", manifest["background_color"]
    assert_not_equal "Assistant.", manifest["description"],
      "The scaffold description is a placeholder; it is what an install prompt shows."
  end

  test "the layout links the manifest and colors the status bar" do
    layout = Rails.root.join("app/views/layouts/application.html.erb").read

    assert_includes layout, "pwa_manifest_path",
      "A manifest nothing links to is a manifest no browser fetches."
    assert_match(/name: "theme-color"|name="theme-color"/, layout)
    # env(safe-area-inset-*) reports zero without it, which would quietly
    # undo the nav toggle's offset from the home indicator.
    assert_includes layout, "viewport-fit=cover"
  end
end
