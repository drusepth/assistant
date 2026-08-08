module Vault
  # "Download my passwords" (PASSWORDS_PLAN §4.7): in-request only, own
  # entries only (what's shared *with* you belongs to its owner — the
  # Users::Export rule), Bitwarden's CSV columns so leaving us is one import
  # away anywhere.
  class Export
    HEADERS = %w[ folder favorite type name notes fields reprompt login_uri login_username login_password login_totp ].freeze

    def initialize(user, vault_key)
      @user = user
      @vault_key = vault_key
    end

    def csv
      CSV.generate(headers: true) do |csv|
        csv << HEADERS
        @user.credentials.order(:created_at).each do |credential|
          secrets = credential.read_secrets(@user, @vault_key)
          next if secrets.nil? # lost in a reset — metadata survives in the archive export

          csv << row_for(credential, secrets)
        end
      end
    end

    private
      def row_for(credential, secrets)
        notes = secrets["notes"].to_s
        extra = (credential.secret_field_names - %w[ password totp notes ])
          .filter_map { |field| "#{field}: #{secrets[field]}" if secrets[field].present? }
        notes = [ notes.presence, *extra ].compact.join("\n")

        [ credential.kind_settings[:label], nil,
          credential.kind == "note" ? "note" : "login",
          credential.name, notes.presence, nil, nil,
          credential.url, credential.username,
          secrets["password"], secrets["totp"] ]
      end
  end
end
