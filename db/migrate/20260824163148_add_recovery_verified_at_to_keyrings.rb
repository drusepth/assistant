# `recovery_confirmed_at` records that someone clicked "I saved it". That is
# a promise, and for the passwords vault it is enough — a lost vault there
# costs a round of password resets at the websites themselves.
#
# The diary has no such fallback: nobody else holds a key to it, so a kit
# that turns out to be mistyped or missing is the whole journal. So it gets
# a stronger fact — the code was pasted back and actually opened the vault.
class AddRecoveryVerifiedAtToKeyrings < ActiveRecord::Migration[8.1]
  def change
    add_column :keyrings, :recovery_verified_at, :datetime
  end
end
