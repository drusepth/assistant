class CreateAccessGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :access_grants do |t|
      t.references :grantor, null: false, foreign_key: { to_table: :users }
      t.references :grantee, null: false, foreign_key: { to_table: :users }
      t.references :subject, null: false, polymorphic: true

      t.timestamps
    end
    add_index :access_grants, [ :grantor_id, :grantee_id, :subject_type, :subject_id ],
      unique: true, name: "index_access_grants_uniqueness"
    add_index :access_grants, [ :grantee_id, :subject_type, :subject_id ],
      name: "index_access_grants_on_grantee_and_subject"
  end
end
