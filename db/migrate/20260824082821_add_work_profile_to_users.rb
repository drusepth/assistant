class AddWorkProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :job_title, :string
    add_column :users, :employer, :string
  end
end
