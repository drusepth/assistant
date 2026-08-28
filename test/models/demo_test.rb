require "test_helper"
require Rails.root.join("db/demo")

# The demo household (db/demo.rb) is the only seed nothing else exercises,
# so without this it rots quietly: a validation tightens or a column is
# renamed, and nobody finds out until the next time someone wants
# screenshots. Running the whole thing once is the cheapest honest check.
class DemoTest < ActiveSupport::TestCase
  # The seed tags into the *whole* seeded taxonomy, and the section
  # fixtures carry only the subset the other tests needed — no taxes,
  # assets, immigration or voting. db/seeds.rb is idempotent and keyed on
  # slug, so loading it here fills the gaps and leaves the fixtures alone.
  setup do
    Rails.application.load_seed
    @household = Demo.seed!
  end
  teardown { Demo.reset! }

  test "the seed builds a whole household" do
    assert_equal 3, @household.users.count
    assert @household.users.any?(&:admin?)

    kay = @household.users.find_by(email_address: "kay@example.com")
    assert kay.people.count >= 8, "the address book should have a circle in it"
    assert_equal 2, kay.pets.count
    assert kay.events.any?, "there should be a calendar"
    assert kay.tasks.any?, "there should be a board"
    assert kay.goals.any?, "there should be goals with steps"
    assert kay.recipes.count >= 5
    assert kay.trips.count >= 2
    assert kay.budget_categories.any?
    assert SpendingTransaction.where(user_id: kay.id).count >= 50, "three months of ledger"
  end

  # The lore's whole point (db/demo.rb's header): one event in the family's
  # life shows up in several sections at once, because that is the app's
  # architectural claim. A demo where each section held unrelated filler
  # would quietly contradict it.
  test "the layoff is filed across several sections at once" do
    danny = @household.users.find_by(email_address: "danny@example.com")
    overtime = danny.notes.detect { |note| note.title == "The overtime Kessler still owes" }

    assert overtime, "the wage-claim note should exist"
    assert_equal %w[ career money rights ], overtime.sections.map(&:slug).sort
  end

  # Sealed containers can only be written by something holding the
  # password (D-vault-crypto, D-diary-vault). That the seed manages it is
  # worth pinning, because the failure mode is a demo whose vault is empty
  # and whose diary silently isn't there.
  test "the sealed containers are real and readable" do
    kay = @household.users.find_by(email_address: "kay@example.com")
    vault_key = kay.keyring.unlock(Demo::PASSWORD)

    assert vault_key, "the demo password should open the keyring"
    assert kay.credentials.count >= 4
    assert kay.diary_entries.count >= 3

    wifi = kay.credentials.detect { |c| c.name == "Prentice Street wifi" }
    assert_equal "roastedokra1997", wifi.read_secrets(kay, vault_key)["password"]
  end

  # Sharing a credential is two writes: the visibility grant and the item
  # key re-wrapped to the grantee. Granting without wrapping would give
  # Danny a row he cannot decrypt, which looks fine until someone clicks it.
  test "a shared credential is decryptable by the person it was shared with" do
    kay, danny = %w[ kay@example.com danny@example.com ].map { |e| @household.users.find_by(email_address: e) }
    wifi = kay.credentials.detect { |c| c.name == "Prentice Street wifi" }

    assert wifi.visible_to?(danny), "Danny should see the shared credential"
    assert_equal "roastedokra1997",
      wifi.read_secrets(danny, danny.keyring.unlock(Demo::PASSWORD))["password"]
  end

  # Times in the seed are wall-clock times in the family's kitchen. Parsed
  # in the process default they land four hours out, and a 9am church
  # service renders as 5am — which is exactly what happened first time.
  test "events land at the wall-clock time they were written as" do
    kay = @household.users.find_by(email_address: "kay@example.com")
    service = kay.events.detect { |event| event.title.start_with?("Sunday kitchen") }

    assert_equal "09:00", service.starts_at.in_time_zone(@household.zone).strftime("%H:%M")
  end

  test "reset leaves nothing behind" do
    kay = @household.users.find_by(email_address: "kay@example.com")

    Demo.reset!

    assert_nil Household.find_by(name: Demo.household_name)
    assert_empty Section.custom, "the pet and hobby lenses should go with the household"
    assert_empty SpendingTransaction.where(user_id: kay.id), "the mirror rows have no foreign key to cascade"
  end
end
