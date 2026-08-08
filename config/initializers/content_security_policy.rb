# A real Content-Security-Policy (PASSWORDS_PLAN §4.8): for a server-side
# password vault, XSS is the one attack class that turns "encrypted at rest"
# into "no vault at all" — script running as the user can call the reveal
# endpoint. So scripts are nonce-gated app-wide (the importmap inline tag
# picks the nonce up automatically), plugins are off, and nobody can frame
# us. Styles allow inline because Tailwind utilities and ERB-computed style
# attributes (progress widths) are everywhere; img/connect allow https for
# the D-storage-seam S3 redirect and direct-upload paths.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :blob, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.connect_src :self, :https
    policy.frame_ancestors :self
    policy.base_uri    :self
    policy.form_action :self
  end

  # Session-stable rather than per-request random: the app serves etag'd
  # HTML (stale_when_importmap_changes) and Turbo restores cached bodies, so
  # a nonce that changed every request would stop matching the body the
  # browser actually re-renders. An attacker can't read another session's id.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[ script-src ]
end
