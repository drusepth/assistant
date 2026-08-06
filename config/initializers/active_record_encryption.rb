# Self-hosted instances shouldn't have to run credentials ceremonies (the
# one-command-install principle, D14): if no Active Record encryption keys
# are configured, generate them once and persist them alongside the
# databases in storage/ — the volume the user already treats as their life
# archive, so backups carry the keys with the data they decrypt.
Rails.application.configure do
  next if config.active_record.encryption.primary_key.present?

  path = Rails.root.join("storage", "active_record_encryption.yml")
  unless File.exist?(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, {
      "primary_key" => SecureRandom.alphanumeric(32),
      "deterministic_key" => SecureRandom.alphanumeric(32),
      "key_derivation_salt" => SecureRandom.alphanumeric(32)
    }.to_yaml)
    File.chmod(0o600, path)
  end

  keys = YAML.safe_load_file(path)
  config.active_record.encryption.primary_key = keys.fetch("primary_key")
  config.active_record.encryption.deterministic_key = keys.fetch("deterministic_key")
  config.active_record.encryption.key_derivation_salt = keys.fetch("key_derivation_salt")

  # Instances older than this initializer have plaintext api_keys until the
  # backfill migration re-saves them; keep reading them in the meantime.
  config.active_record.encryption.support_unencrypted_data = true
end
