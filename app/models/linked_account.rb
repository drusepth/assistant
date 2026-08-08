# Connected outside services (D26): the linking layer that lets the
# assistant reach the accounts a user already lives in — mail, address
# book, calendar, social networks. Linked from Settings; one row per
# provider per user, except `multi: true` providers (email), which allow
# one row per mailbox distinguished by a required label.
#
# Access is scope-gated per link. Every provider scope is ON by default
# ("link it and the assistant can use it"), and we store only the scopes
# the user switched OFF — the same enabled-unless-disabled convention as
# section toggles (D4), so a scope added to a provider later is granted to
# existing links without backfill. Anything that reads through a link must
# go through `allows?`.
#
# Providers are first-party registry entries, not user data (D11): adding
# a service = one entry here; ones with a live consumer name their
# sync_service, ones that sync in the background their sync_every.
# Credentials are serialized JSON encrypted at rest with the same
# per-instance keys that cover model_profiles.api_key (the email plan's
# E0 pass closed that D26 follow-up).
class LinkedAccount < ApplicationRecord
  PROVIDERS = {
    "email" => {
      label: "Email",
      description: "Any mailbox over IMAP — Gmail, Zoho, iCloud, Fastmail, or your own server.",
      multi: true,
      sync_service: "Email::ImapSync",
      sync_every: 15.minutes,
      fields: [
        { key: "host", label: "IMAP server", placeholder: "imap.gmail.com" },
        { key: "username", label: "Email address", placeholder: "you@example.com" },
        { key: "password", label: "Password", secret: true,
          hint: "Most providers want an app-specific password here, not your login password." }
      ],
      scopes: {
        "read_inbox" => "Read incoming mail",
        "read_archive" => "Search older mail",
        "send" => "Send mail on your behalf"
      }
    },
    "contacts" => {
      label: "Address book",
      description: "Your contacts over CardDAV — iCloud, Fastmail, Nextcloud, or any address-book server. Syncs into People.",
      sync_service: "People::CarddavSync",
      sync_every: 1.hour,
      fields: [
        { key: "server_url", label: "CardDAV server", placeholder: "https://contacts.example.com/…" },
        { key: "username", label: "Username", placeholder: "you@example.com" },
        { key: "password", label: "Password", secret: true,
          hint: "Most providers want an app-specific password here, not your login password." }
      ],
      scopes: {
        "read" => "Read your contacts",
        "write" => "Add and update contacts"
      }
    },
    "calendar" => {
      label: "Calendar",
      description: "Your calendars over CalDAV — iCloud, Fastmail, Nextcloud, or any calendar server. Syncs into Calendar.",
      sync_service: "Events::CaldavSync",
      sync_every: 1.hour,
      fields: [
        { key: "server_url", label: "CalDAV server", placeholder: "https://caldav.example.com/…" },
        { key: "username", label: "Username", placeholder: "you@example.com" },
        { key: "password", label: "Password", secret: true,
          hint: "Most providers want an app-specific password here, not your login password." }
      ],
      scopes: {
        "read" => "Read your calendars",
        "write" => "Add and update events"
      }
    },
    "facebook" => {
      label: "Facebook",
      description: "Your Facebook profile, friends, and events, via a Graph API token.",
      fields: [
        { key: "access_token", label: "Access token", secret: true,
          hint: "Generate a user token at developers.facebook.com → Tools → Graph API Explorer." }
      ],
      scopes: {
        "profile" => "Profile and about info",
        "friends" => "Friends list",
        "events" => "Events and invitations",
        "posts" => "Posts and timeline"
      }
    },
    "linkedin" => {
      label: "LinkedIn",
      description: "Your professional profile and network, via an API token.",
      fields: [
        { key: "access_token", label: "Access token", secret: true,
          hint: "Generate a token for your own app at linkedin.com/developers." }
      ],
      scopes: {
        "profile" => "Profile, positions, and skills",
        "connections" => "Connections",
        "jobs" => "Saved jobs and job activity"
      }
    }
  }.freeze

  belongs_to :user

  # Encrypted at rest; serialize must come first so encryption wraps the
  # JSON coder (hash in Ruby, ciphertext in the file).
  serialize :credentials, coder: JSON
  encrypts :credentials

  # Unlinking purges this mailbox's mirror (EMAIL_PLAN.md §3); promoted
  # primitives are the user's items and survive.
  before_destroy { Email::Mirror.purge(self) if provider == "email" }

  validates :provider, inclusion: { in: PROVIDERS.keys }
  validates :provider, uniqueness: { scope: :user_id }, unless: :multi?
  validates :label, presence: true, uniqueness: { scope: %i[ user_id provider ] }, if: :multi?
  validate :required_credentials_present

  # Unknown providers fail the inclusion validation; fall back so the other
  # validations can still run without raising.
  def provider_settings = PROVIDERS.fetch(provider) { { label: provider, fields: [], scopes: {} } }
  def provider_label = provider_settings[:label]
  def scopes = provider_settings[:scopes]
  def multi? = provider_settings[:multi].present?

  # "Email — Work" for multi-link providers, "Calendar" otherwise.
  def display_name = label.present? ? "#{provider_label} — #{label}" : provider_label

  # The one question consumers ask. Unknown scopes are never allowed, so a
  # typo in a future sync job fails closed rather than leaking data.
  def allows?(scope)
    scopes.key?(scope.to_s) && !disabled_scopes.include?(scope.to_s)
  end

  def enabled_scopes = scopes.keys - disabled_scopes
  def full_access? = (scopes.keys & disabled_scopes).empty?

  # A provider with a live sync consumer names it in the registry;
  # SyncLinkedAccountJob dispatches through this.
  def sync_service = provider_settings[:sync_service]&.constantize
  def syncable? = provider_settings[:sync_service].present?

  # Per-link user settings (the email dials land here in later passes).
  # Stored sparse — only what the user changed — so defaults can evolve.
  def setting(key) = settings[key.to_s]
  def paused? = setting(:paused) == true

  # Background sync (E0): a link is due when its registry cadence has
  # elapsed. The recurring fan-out asks this every few minutes. An email
  # link with urgent alerts on polls tighter (E3) — a "court date moved"
  # alert that arrives 14 minutes late has lost most of its point.
  def sync_every
    base = provider_settings[:sync_every]
    return 3.minutes if base && provider == "email" && setting(:alerts) == true
    base
  end
  def sync_due?
    syncable? && !paused? && sync_every.present? &&
      (synced_at.nil? || synced_at < sync_every.ago)
  end

  private
    def required_credentials_present
      provider_settings[:fields].each do |field|
        if credentials[field[:key]].blank?
          errors.add(:base, "#{field[:label]} can't be blank")
        end
      end
    end
end
