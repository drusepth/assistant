# The audit trail was credential-shaped because credentials were the only
# sealed container. The diary is the second (D-vault-sealed), so the
# subject becomes polymorphic — and the passwords page learns to show only
# its own container's events plus the vault-wide ones.
class MakeVaultEventSubjectPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :vault_events, :subject_type, :string
    add_column :vault_events, :subject_id, :integer
    add_index :vault_events, [ :subject_type, :subject_id ]

    execute <<~SQL.squish
      UPDATE vault_events
      SET subject_type = 'Credential', subject_id = credential_id
      WHERE credential_id IS NOT NULL
    SQL

    remove_column :vault_events, :credential_id
  end

  def down
    add_column :vault_events, :credential_id, :integer
    add_index :vault_events, :credential_id

    execute <<~SQL.squish
      UPDATE vault_events SET credential_id = subject_id WHERE subject_type = 'Credential'
    SQL

    remove_index :vault_events, [ :subject_type, :subject_id ]
    remove_column :vault_events, :subject_type
    remove_column :vault_events, :subject_id
  end
end
