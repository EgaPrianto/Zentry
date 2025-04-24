# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
require 'faker'

# Clear existing data
puts "Clearing existing data..."
Follow.destroy_all
SleepEntry.destroy_all
User.destroy_all

# Create Users
puts "Creating users..."
users = 20.times.map do
  { name: Faker::Name.name }
end

created_users = users.map { |user_attrs| User.create!(user_attrs) }
puts "Created #{created_users.size} users"

# Create Sleep Entries
puts "Creating sleep entries..."
sleep_entries_data = []

# For each user, create 3-5 sleep entries
created_users.each do |user|
  # Random number of entries between 3 and 5
  rand(3..5).times do
    # Random sleep duration between 4 and 10 hours, converted to milliseconds
    duration = rand(4*60..10*60).minutes.to_i
    # Random date within the last 2 weeks
    created_at = rand(1..14).days.ago

    sleep_entries_data << {
      user_id: user.id,
      sleep_duration: duration,
      created_at: created_at,
      updated_at: created_at
    }
  end
end

sleep_entries = SleepEntry.create!(sleep_entries_data)
puts "Created #{sleep_entries.size} sleep entries"

# Create Follows
puts "Creating follows..."
follows_data = []

created_users.each do |user|
  # Each user follows 1-3 other users
  followees = created_users.sample(rand(1..3))

  followees.each do |followee|
    # Don't let users follow themselves
    next if user.id == followee.id

    follows_data << {
      user_id: user.id,
      follower_id: followee.id  # This matches your schema where follower_id represents the followed_user
    }
  end
end

# Use create instead of create! to ignore duplicates
follows_data.each do |follow_data|
  Follow.create(follow_data)
end

puts "Created #{Follow.count} follows"

puts "Seed data generation complete!"
