require "test_helper"

# Source-level pins on the screenshot registry (docs/ABOUT_PLAN.md §7).
#
# Three things must agree and have no way of noticing when they don't: the
# registry (About::Shot), the views that ask for shots by name, and the
# files a capture run produced. The failure modes are all silent — a broken
# image on a public page, or megabytes of orphaned WEBP nobody renders — so
# they are pinned here rather than left to whoever next opens the site.
class AboutShotsTest < ActiveSupport::TestCase
  VIEWS = Rails.root.glob("app/views/about/**/*.erb")
  CALL = /about_screenshot\(\s*["']([a-z_]+)["']/

  test "every shot a view asks for is registered" do
    unknown = requested.reject { |name, _| About::Shot.find(name) }

    assert_empty unknown.keys, <<~MSG
      These views call about_screenshot with a name the registry doesn't
      know, so they render nothing at all — silently:

      #{unknown.map { |name, where| "#{name} (#{where.join(', ')})" }.join("\n")}
    MSG
  end

  test "every registered shot has been captured" do
    missing = About::Shot::LIST.reject { |shot| About::Shot.directory.join("#{shot.name}.webp").exist? }

    assert_empty missing.map(&:name), <<~MSG
      These shots are registered but no image exists, so every page asking
      for one renders without it. Capture them:

        bin/rails screenshots:capture
    MSG
  end

  test "no captured image is left unrendered" do
    on_disk = About::Shot.directory.glob("*.webp").map { |file| file.basename(".webp").to_s }

    assert_empty on_disk - About::Shot.names, <<~MSG
      These images are in the repository but no registry entry names them,
      so nothing renders them and they are pure weight. Register them or
      delete them.
    MSG
  end

  # Committed forever, and shipped to every visitor. WEBP at this size is
  # comfortably under; a PNG that slipped in would not be.
  test "no screenshot is unreasonably large" do
    heavy = About::Shot.directory.glob("*.webp").select { |file| file.size > 250.kilobytes }

    assert_empty heavy.map { |f| "#{f.basename} (#{(f.size / 1024.0).round}K)" },
      "screenshots are committed and served to everyone; keep them small"
  end

  private
    def requested
      VIEWS.each_with_object(Hash.new { |h, k| h[k] = [] }) do |path, found|
        path.read.scan(CALL).flatten.each do |name|
          found[name] << path.relative_path_from(Rails.root).to_s
        end
      end
    end
end
