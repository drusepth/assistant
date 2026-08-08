module Vault
  # Sharing needs two writes in lockstep (D-vault-crypto): the AccessGrant
  # (visibility — the D9 surface, unchanged) and the CredentialKey (the item
  # key wrapped to the grantee's public key). Revoke destroys both and then
  # rotates the item key, so a kept copy of the old wrap opens nothing in
  # any future snapshot of the database.
  class Share
    Result = Struct.new(:shared, :names, :error)

    def initialize(credential, owner, vault_key)
      @credential = credential
      @owner = owner
      @vault_key = vault_key
    end

    def grant(grantees)
      item_key = @credential.unwrap_item_key(@owner, @vault_key)
      return Result.new(0, [], "This entry's secret is lost — re-enter it before sharing.") if item_key.nil?

      names = []
      grantees.each do |grantee|
        next if grantee.id == @owner.id
        next if @credential.credential_keys.exists?(user: grantee)
        next if grantee.keyring.nil? # ask them to sign in once first

        ApplicationRecord.transaction do
          AccessGrant.find_or_create_by!(grantor: @owner, grantee: grantee, subject: @credential)
          @credential.credential_keys.create!(user: grantee,
            wrapped_item_key: Vault::Crypto.rsa_wrap(grantee.keyring.public_key, item_key))
        end
        VaultEvent.record("shared", user: @owner, actor: @owner, credential: @credential, subject_user: grantee)
        names << grantee.name
      end

      Result.new(names.size, names, nil)
    end

    def revoke(grantee)
      item_key = @credential.unwrap_item_key(@owner, @vault_key)
      payload = item_key && @credential.read_secrets_with_item_key(item_key)
      return false if payload.nil?

      ApplicationRecord.transaction do
        @credential.access_grants.where(grantor: @owner, grantee: grantee).destroy_all # callback drops the key row
        remaining = [ @owner ] + @credential.shared_with.reject { |user| user.id == grantee.id }
        @credential.rotate_secrets!(payload, holders: remaining)
      end
      VaultEvent.record("unshared", user: @owner, actor: @owner, credential: @credential, subject_user: grantee)
      true
    end
  end
end
