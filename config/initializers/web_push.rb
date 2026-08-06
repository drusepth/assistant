# Per-instance VAPID keys for browser push (D22) — same pattern as the
# encryption keys: generated once on first boot, persisted in storage/ so
# no account with any third party is ever needed.
Rails.application.configure do
  path = Rails.root.join("storage", "web_push_vapid.yml")
  unless File.exist?(path)
    FileUtils.mkdir_p(File.dirname(path))
    keys = WebPush.generate_key
    File.write(path, { "public_key" => keys.public_key, "private_key" => keys.private_key }.to_yaml)
    File.chmod(0o600, path)
  end

  vapid = YAML.safe_load_file(path)
  config.x.web_push.public_key = vapid.fetch("public_key")
  config.x.web_push.private_key = vapid.fetch("private_key")
end
