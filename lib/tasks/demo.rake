# The demo household (db/demo.rb) — a published, fictional family for
# screenshots and for having something to look at while building.
#
# Never wired into `db:seed`: that runs on every install and seeds the
# section taxonomy, and a real household's first login must not find a
# fictional one already living there.
namespace :demo do
  desc "Seed the demo household (destroys and rebuilds it). Refuses in production without DEMO_FORCE=1."
  task seed: :environment do
    if Rails.env.production? && ENV["DEMO_FORCE"] != "1"
      abort "Refusing to seed demo data in production. Set DEMO_FORCE=1 if you really mean it."
    end

    # The demo tags itself into the seeded taxonomy, so that has to exist
    # first. db/seeds.rb is idempotent by design, so running it here is
    # free on an instance that already has it.
    Rails.application.load_seed
    require Rails.root.join("db/demo")

    household = Demo.seed!

    puts "Seeded #{household.name}."
    household.users.order(:id).each do |user|
      puts "  #{user.name.ljust(20)} #{user.email_address.ljust(24)} #{Demo::PASSWORD}#{' (admin)' if user.admin?}"
    end
  end

  desc "Remove the demo household and everything it owns."
  task reset: :environment do
    require Rails.root.join("db/demo")

    Demo.reset!
    puts "Demo household removed."
  end
end
