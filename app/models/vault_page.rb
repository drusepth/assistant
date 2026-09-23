# The pages under the sidebar's Vault heading, as a registry the picker
# (D-vault-picker), onboarding step 1, and the sidebar all read — so adding
# a page to the Vault is one row here, not three edits that can drift.
#
# "Vault" here is the sidebar group — the owned repository of your stuff —
# not the sealed password vault (D-passwords-vault), which is one row in it.
#
# `requires` names a precondition beyond the user's choice: Mail has
# nothing to show until an email account is linked, so it stays out of the
# sidebar until then however it's switched.
class VaultPage
  Entry = Data.define(:slug, :name, :icon, :route, :blurb, :requires)

  ALL = [
    Entry.new(slug: "people", name: "Address Book", icon: :users, route: :people_path, requires: nil,
      blurb: "Everyone you know and what matters about them — birthdays, how you met, what you last talked about."),
    Entry.new(slug: "photos", name: "Photos", icon: :photo, route: :photos_path, requires: nil,
      blurb: "Your household's photos and albums, private until you share them."),
    Entry.new(slug: "recipes", name: "Recipes", icon: :book_open, route: :recipes_path, requires: nil,
      blurb: "A recipe box and recipe books you can share with the household or send to a friend by link."),
    Entry.new(slug: "documents", name: "Documents", icon: :document, route: :documents_path, requires: nil,
      blurb: "Leases, bills, test results — upload a file or a photo of one and the app reads it."),
    Entry.new(slug: "notes", name: "Notes", icon: :note, route: :notes_path, requires: nil,
      blurb: "Everything you've told the assistant about yourself, in one place you can read and edit."),
    Entry.new(slug: "mail", name: "Mail", icon: :envelope, route: :mail_index_path, requires: :email_account,
      blurb: "Your inboxes, sorted and summarized, with the urgent ones flagged. Appears once you connect an email account in Settings."),
    Entry.new(slug: "passwords", name: "Passwords", icon: :key, route: :credentials_path, requires: nil,
      blurb: "A password manager encrypted with a key only you hold, with one-time codes and household sharing."),
    Entry.new(slug: "diary", name: "Diary", icon: :pencil, route: :diary_entries_path, requires: nil,
      blurb: "A private journal, sealed with your own key — nobody else in the household, admins included, can read it.")
  ].freeze

  SLUGS = ALL.map(&:slug).freeze

  def self.find!(slug)
    ALL.find { |page| page.slug == slug } or raise ActiveRecord::RecordNotFound, "No vault page #{slug.inspect}"
  end
end
