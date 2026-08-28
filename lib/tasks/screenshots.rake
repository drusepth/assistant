# The /about screenshot pipeline (docs/ABOUT_PLAN.md §7).
#
# The capture is a system test — it needs a browser and a running server,
# which Rails already knows how to arrange — so this task is a readable name
# for running that one file. `bin/rails test` skips test/system, so nothing
# here fires during an ordinary test run.
namespace :screenshots do
  desc "Capture the /about screenshots from the demo household (needs a browser)."
  task :capture do
    sh "bin/rails test test/system/about_screenshots_test.rb"
  end

  desc "List the registered shots and whether each has been captured."
  task list: :environment do
    About::Shot::LIST.each do |shot|
      file = About::Shot.directory.join("#{shot.name}.webp")
      size = file.exist? ? "#{(file.size / 1024.0).round}K" : "missing"
      puts "  #{shot.name.ljust(12)} #{shot.path.ljust(22)} #{size}"
    end
  end
end
