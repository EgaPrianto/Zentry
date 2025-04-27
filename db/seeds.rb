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

# Reset Elasticsearch indices
puts "Resetting Elasticsearch indices..."
# Delete existing indices
%w[sleep_entries feeds].each do |index_name|
  if Elasticsearch::Connection.index_exists?(index_name)
    Elasticsearch::Connection.delete_index(index_name)
    puts "Deleted index: #{index_name}"
  end
end
# Create fresh indices
Elasticsearch::IndexSetup.setup_indices
puts "Created fresh Elasticsearch indices"

# Clear existing data
puts "Clearing existing data..."
Follow.destroy_all
SleepEntry.destroy_all
User.destroy_all

# Create Users
puts "Creating regular users..."
users = 20.times.map do
  { name: Faker::Name.name }
end

created_users = users.map { |user_attrs| User.create!(user_attrs) }
puts "Created #{created_users.size} regular users"

# Create celebrity users (users with 10,000+ followers)
puts "Creating celebrity users..."
celebrity_users = 2.times.map do
  { name: "#{Faker::Name.name} (Celebrity)" }
end

created_celebrities = celebrity_users.map { |user_attrs| User.create!(user_attrs) }
puts "Created #{created_celebrities.size} celebrity users"

# Create Sleep Entries
puts "Creating sleep entries..."
sleep_entries_count = 0

# For each user (including celebrities), create 3-5 sleep entries
(created_users + created_celebrities).each do |user|
  # Random number of entries between 3 and 5
  rand(3..5).times do
    # Random sleep duration between 4 and 10 hours
    duration = rand(4*60..10*60).minutes
    # Random date within the last 2 weeks
    created_at = rand(1..14).days.ago
    started_at = created_at - duration

    sleep_entry_params = {
      user_id: user.id,
      sleep_duration: duration.to_i,
      start_at: started_at
    }
    # Use the SleepEntryService to create the entry
    result = SleepEntryService.create_sleep_entry(user.id, sleep_entry_params)
    if result[:success]
      sleep_entries_count += 1
    else
      puts "Failed to create sleep entry: #{result[:error]}"
    end
  end
end

puts "Created #{sleep_entries_count} sleep entries"

# Create Follows
puts "Creating follows for regular users..."
follows_data = []

created_users.each do |user|
  # Each user follows 1-3 other regular users
  followees = created_users.sample(rand(1..3))

  # Each user also follows 1-2 celebrities
  celebrity_followees = created_celebrities.sample(rand(1..2))

  (followees + celebrity_followees).each do |followee|
    # Don't let users follow themselves
    next if user.id == followee.id

    follows_data << {
      user_id: user.id,
      follower_id: followee.id
    }
  end
end

# Create many followers for celebrity users
puts "Creating 10,000+ followers for each celebrity user..."
created_celebrities.each do |celebrity|
  # Create a large number of followers (10,000+) for each celebrity
  follower_count = 10_000 + rand(1..1000)

  puts "Creating #{follower_count} followers for celebrity #{celebrity.name}..."

  # Create followers in batches to avoid memory issues
  batch_size = 1000
  (follower_count / batch_size).times do |batch|
    batch_followers = []
    batch_size.times do
      # Create a generic follower user
      follower = User.create!(name: Faker::Name.name)

      # Create the follow relationship
      batch_followers << {
        user_id: celebrity.id,
        follower_id: follower.id
      }
    end

    # Bulk insert the follows
    Follow.insert_all(batch_followers)
    print "."
  end
  puts " Done!"
end

# Use create instead of create! to ignore duplicates
follows_data.each do |follow_data|
  Follow.create(follow_data)
end

puts "Created #{Follow.count} follows"

# Verify celebrity status
created_celebrities.each do |celebrity|
  follower_count = Follow.where(user_id: celebrity.id).count
  puts "Celebrity #{celebrity.name} has #{follower_count} followers"
  puts "Is treated as celebrity by the system: #{Elasticsearch::FeedStrategy.use_fan_in?(celebrity.id) ? 'YES' : 'NO'}"
end

puts "Seed data generation complete!"
