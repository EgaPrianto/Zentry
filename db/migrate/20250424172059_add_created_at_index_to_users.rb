class AddCreatedAtIndexToUsers < ActiveRecord::Migration[8.0]
  def change
    # Adding an index to the created_at column of the users table
    add_index :users, :created_at

    add_foreign_key :sleep_entries, :users, column: :user_id
  end
end
