# Connected outside services (D21): the linking layer that lets the
# assistant reach the accounts a user already lives in — mail, address
# book, calendar, social networks. One row per user per provider,
# connected from Settings.
#
# Access is scope-gated per link. Every provider scope is ON by default
# ("link it and the assistant can use it"), and we store only the scopes
# the user switched OFF — the same enabled-unless-disabled convention as
# section toggles (D4), so a scope added to a provider later is granted to
# existing links without backfill. Anything that reads through a link must
# go through `allows?`.
#
# Providers are first-party registry entries, not user data (D11): adding
# a service = one entry here. Credentials are a plaintext JSON blob for
# now — the same deliberate encryption deferral as model_profiles.api_key
# (D10/D14). Nothing syncs yet; this is the configuration surface future
# importers, tools, and watchers consume.
class LinkedAccount < ApplicationRecord
  PROVIDERS = {
    "email" => {
      label: "Email",
      description: "Any mailbox over IMAP — Gmail, Outlook, iCloud, Fastmail, or your own server.",
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
      description: "Your contacts over CardDAV — Google, iCloud, Nextcloud, or any address-book server.",
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
      description: "Your calendars over CalDAV — Google, iCloud, Nextcloud, or any calendar server.",
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

  validates :provider, inclusion: { in: PROVIDERS.keys }
  validates :provider, uniqueness: { scope: :user_id }
  validate :required_credentials_present

  # Unknown providers fail the inclusion validation; fall back so the other
  # validations can still run without raising.
  def provider_settings = PROVIDERS.fetch(provider) { { label: provider, fields: [], scopes: {} } }
  def label = provider_settings[:label]
  def scopes = provider_settings[:scopes]

  # The one question consumers ask. Unknown scopes are never allowed, so a
  # typo in a future sync job fails closed rather than leaking data.
  def allows?(scope)
    scopes.key?(scope.to_s) && !disabled_scopes.include?(scope.to_s)
  end

  def enabled_scopes = scopes.keys - disabled_scopes
  def full_access? = (scopes.keys & disabled_scopes).empty?

  private
    def required_credentials_present
      provider_settings[:fields].each do |field|
        if credentials[field[:key]].blank?
          errors.add(:base, "#{field[:label]} can't be blank")
        end
      end
    end
end
