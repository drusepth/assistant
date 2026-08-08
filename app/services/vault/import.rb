module Vault
  # One CSV away from leaving a corporate manager (PASSWORDS_PLAN §6):
  # header-set sniffing over the exports of Bitwarden, LastPass, 1Password,
  # Chrome/Edge, and Firefox, the People::Import dedupe convention (exact
  # name+username+url matches skip), all in-request — the file already
  # carries plaintext and must never transit the job queue.
  class Import
    class Error < StandardError; end

    Result = Struct.new(:imported, :skipped)

    # Recognized by the presence of these headers (subset match, order-free).
    FORMATS = [
      { signature: %w[ login_uri login_username login_password ], label: "Bitwarden",
        name: "name", username: "login_username", password: "login_password",
        url: "login_uri", totp: "login_totp", notes: "notes", type: "type" },
      { signature: %w[ url username password grouping ], label: "LastPass",
        name: "name", username: "username", password: "password",
        url: "url", totp: "totp", notes: "extra" },
      { signature: %w[ title username password ], label: "1Password",
        name: "title", username: "username", password: "password",
        url: "url", totp: "otpauth", notes: "notes" },
      { signature: %w[ name url username password ], label: "Chrome",
        name: "name", username: "username", password: "password",
        url: "url", notes: "note" },
      { signature: %w[ url username password guid ], label: "Firefox",
        name: nil, username: "username", password: "password",
        url: "url" }
    ].freeze

    def initialize(user, csv_text)
      @user = user
      @csv_text = csv_text
    end

    def call
      rows = parse
      format = detect_format(rows.headers)

      existing = @user.credentials.map { |c| fingerprint(c.name, c.username, c.url) }.to_set
      imported = skipped = 0

      rows.each do |row|
        attributes = extract(row, format)
        next if attributes.nil?

        if existing.include?(fingerprint(attributes[:name], attributes[:username], attributes[:url]))
          skipped += 1
          next
        end

        credential = @user.credentials.new(kind: attributes[:kind], name: attributes[:name],
          username: attributes[:username], url: attributes[:url])
        next unless credential.valid?

        credential.write_secrets!(attributes[:secrets])
        existing << fingerprint(attributes[:name], attributes[:username], attributes[:url])
        imported += 1
      end

      Result.new(imported, skipped)
    end

    private
      def parse
        CSV.parse(@csv_text.to_s.sub(/\A\xEF\xBB\xBF/, ""), headers: true)
      rescue CSV::MalformedCSVError
        raise Error, "That file didn't parse as CSV — export from your password manager and try again."
      end

      def detect_format(headers)
        normalized = Array(headers).compact.map { |h| h.to_s.strip.downcase }
        FORMATS.find { |format| (format[:signature] - normalized).empty? } or
          raise Error, "Didn't recognize those CSV columns — Bitwarden, LastPass, 1Password, Chrome, and Firefox exports are supported."
      end

      def extract(row, format)
        fetch = ->(key) { key && row[row.headers.find { |h| h.to_s.strip.downcase == key }].presence }

        url = fetch.call(format[:url])
        name = fetch.call(format[:name]) || host_from(url)
        return nil if name.blank?

        secure_note = format[:type] && fetch.call(format[:type]) == "note"
        secrets = {
          "password" => fetch.call(format[:password]),
          "totp" => normalize_totp(fetch.call(format[:totp])),
          "notes" => fetch.call(format[:notes])
        }.compact_blank

        {
          kind: secure_note ? "note" : "login",
          name: name, username: fetch.call(format[:username]), url: url,
          secrets: secure_note ? secrets.slice("notes") : secrets
        }
      end

      def normalize_totp(value)
        return nil if value.blank?

        Vault::Crypto.normalize_totp_secret(value)
      rescue Vault::Crypto::Error
        nil
      end

      def host_from(url)
        URI(url.to_s).host
      rescue URI::Error
        url
      end

      def fingerprint(name, username, url)
        [ name, username, url ].map { |v| v.to_s.strip.downcase }.join("\x00")
      end
  end
end
