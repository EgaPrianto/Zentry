class CreateSleepEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :sleep_entries do |t|
      t.integer :user_id
      t.decimal :sleep_duration, precision: 5, scale: 2, null: true
      t.timestamps
    end
  end
end
