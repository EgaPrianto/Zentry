class CreateSleepEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :sleep_entries do |t|
      t.integer :user_id
      t.integer :sleep_duration
      t.datetime :start_at

      t.timestamps
    end
  end
end
