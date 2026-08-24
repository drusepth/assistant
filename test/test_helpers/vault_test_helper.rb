# The diary gates writing on a *verified* recovery kit (D-diary-vault), so
# almost every diary test needs one. Verifying means generating the kit and
# pasting the code back — the same two steps a person takes — so it lives
# here rather than in eight setup blocks.
module VaultTestHelper
  RECOVERY_CODE = /[A-Z2-9]{6}-[A-Z2-9]{6}-[A-Z2-9]{6}-[A-Z2-9]{6}/

  # Returns the code, in case a test wants to check it later.
  def verify_recovery_kit
    post recovery_credentials_url
    code = response.body[RECOVERY_CODE] or raise "no recovery code in the kit page"

    post recovery_check_credentials_url, params: { recovery_code: code }
    code
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include VaultTestHelper
end
