module Vault
  # Sharing needs two writes in lockstep (D-vault-crypto): the AccessGrant
  # (visibility — the D9 surface, unchanged) and the wrapped item key (the
  # item key encrypted to the grantee's public key). Revoke destroys both and
  # then rotates the item key, so a kept copy of the old wrap opens nothing in
  # any future snapshot of the database.
  #
  # Takes any `VaultSealed` record (D-vault-sealed) — a credential or a diary
  # entry — because the two writes are the same two writes either way.
  class Share
    Result = Struct.new(:shared, :names, :error)

    def initialize(record, owner, vault_key)
      @record = record
      @owner = owner
      @vault_key = vault_key
    end

    def grant(grantees)
      item_key = @record.unwrap_item_key(@owner, @vault_key)
      return Result.new(0, [], lost_message) if item_key.nil?

      names = []
      grantees.each do |grantee|
        next if grantee.id == @owner.id
        next if @record.sealed_keys.exists?(user: grantee)
        next if grantee.keyring.nil? # ask them to sign in once first

        ApplicationRecord.transaction do
          AccessGrant.find_or_create_by!(grantor: @owner, grantee: grantee, subject: @record)
          @record.wrap_item_key_for!(grantee, item_key)
        end
        record_event("shared", grantee)
        names << grantee.name
      end

      Result.new(names.size, names, nil)
    end

    def revoke(grantee)
      item_key = @record.unwrap_item_key(@owner, @vault_key)
      payload = item_key && @record.read_secrets_with_item_key(item_key)
      return false if payload.nil?

      ApplicationRecord.transaction do
        @record.access_grants.where(grantor: @owner, grantee: grantee).destroy_all # callback drops the key row
        remaining = [ @owner ] + @record.shared_with.reject { |user| user.id == grantee.id }
        @record.rotate_secrets!(payload, holders: remaining)
      end
      record_event("unshared", grantee)
      true
    end

    private
      # "Re-enter it" is the right advice for a password and meaningless for
      # a diary entry: there is nothing to re-enter, because the words were
      # the thing that was lost.
      def lost_message
        if @record.is_a?(Credential)
          "This entry's secret is lost — re-enter it before sharing."
        else
          "This entry can't be opened, so it can't be shared."
        end
      end

      def record_event(action, grantee)
        VaultEvent.record(action, user: @owner, actor: @owner, subject: @record, subject_user: grantee)
      end
  end
end
