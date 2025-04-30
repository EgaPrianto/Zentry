require 'rails_helper'

# This system test requires:
# 1. Database to be seeded: `rails db:seed RAILS_ENV=test`
# 2. Server running: `rails server -e test -p 3000`
# Run with: `RAILS_ENV=test rspec spec/system/follow_feed_system_spec.rb`

RSpec.describe "FollowFeedSystemTest", type: :system do
  # Use Capybara.current_session.server
  before(:all) do
    # Check if server is running
    begin
      response = Net::HTTP.get_response(URI('http://localhost:3000/up'))
      unless response.code == '200'
        skip "Test server must be running on http://localhost:3000"
      end
    rescue Errno::ECONNREFUSED
      skip "Test server must be running on http://localhost:3000"
    end

    @current_user_id = 19
    @celebrity_user_id = 21
    @regular_user_id = 18
    today = DateTime.now
    beginning_of_this_week = today - today.wday + 1
    end_of_last_week = beginning_of_this_week - 1   # Sunday of last week
    beginning_of_last_week = end_of_last_week - 6   # Monday of last week
    create_sleep_entry(@current_user_id, 7.hours, beginning_of_last_week + 1.days)
    create_sleep_entry(@celebrity_user_id, 8.hours, beginning_of_last_week + 1.days)

    unfollow_user(@current_user_id, @celebrity_user_id)
    unfollow_user(@current_user_id, @regular_user_id)

  end

  def create_sleep_entry(user_id, duration = 8.hours, start_time = Time.current)
    uri = URI('http://localhost:3000/sleep_entries')
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request['X-User-ID'] = user_id.to_s

    # Calculate end time based on duration

    request.body = {
      sleep_entry: {
        start_at: start_time.strftime('%Y-%m-%d %H:%M:%S'),
        duration: duration.minutes.to_i,
      }
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    {
      status: response.code.to_i,
      body: JSON.parse(response.body)
    }
  end

  # Helper methods for API requests
  def get_feed(user_id)
    uri = URI('http://localhost:3000/sleep_entries/feed')
    request = Net::HTTP::Get.new(uri)
    request['X-User-ID'] = user_id.to_s

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    JSON.parse(response.body)
  end

  def follow_user(user_id, followee_id)
    uri = URI("http://localhost:3000/users/#{followee_id}/follow")
    request = Net::HTTP::Post.new(uri)
    request['X-User-ID'] = user_id.to_s

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    {
      status: response.code.to_i,
      body: JSON.parse(response.body)
    }
  end

  def unfollow_user(user_id, followee_id)
    uri = URI("http://localhost:3000/users/#{followee_id}/follow")
    request = Net::HTTP::Delete.new(uri)
    request['X-User-ID'] = user_id.to_s

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    {
      status: response.code.to_i,
      body: JSON.parse(response.body)
    }
  end

  describe "Follow and feed interactions" do
    context "when following a regular user" do
      it "adds their sleep entries to the current user's feed" do
        # Check initial feed (should be empty as we've cleared follows)
        initial_feed = get_feed(@current_user_id)

        # Follow the regular user
        follow_result = follow_user(@current_user_id, @regular_user_id)
        expect(follow_result[:status]).to eq(201)

        # Wait for Elasticsearch to process
        sleep(2)

        # Check feed after following - should contain regular user's entries
        feed_after = get_feed(@current_user_id)
        expect(feed_after["data"].size).to be > 0

        # Verify the entries are from the followed user
        regular_user_entries = feed_after["data"].select { |e| e["author_id"] == @regular_user_id.to_i }
        expect(regular_user_entries.size).to be > 0

        # Unfollow the user
        unfollow_result = unfollow_user(@current_user_id, @regular_user_id)
        expect(unfollow_result[:status]).to eq(200)

        # Wait for Elasticsearch to process
        sleep(2)

        # Check feed after unfollowing - should be empty again
        feed_after_unfollow = get_feed(@current_user_id)
        expect(feed_after_unfollow["data"].select { |e| e["author_id"] == @regular_user_id.to_i }).to be_empty
      end
    end

    context "when following a celebrity user" do
      it "adds their sleep entries to the current user's feed" do
        # Check initial feed (should be empty as we've cleared follows)
        initial_feed = get_feed(@current_user_id)

        # Follow the celebrity user
        follow_result = follow_user(@current_user_id, @celebrity_user_id)
        expect(follow_result[:status]).to eq(201)

        # Wait for Elasticsearch to process
        sleep(2)

        # Check feed after following - should contain celebrity's entries
        feed_after = get_feed(@current_user_id)
        expect(feed_after["data"].size).to be > 0

        # Verify the entries are from the celebrity
        celebrity_entries = feed_after["data"].select { |e| e["author_id"] == @celebrity_user_id.to_i }
        expect(celebrity_entries.size).to be > 0

        # Unfollow the celebrity user
        unfollow_result = unfollow_user(@current_user_id, @celebrity_user_id)
        expect(unfollow_result[:status]).to eq(200)

        # Wait for Elasticsearch to process
        sleep(2)

        # Check feed after unfollowing - should be empty again
        feed_after_unfollow = get_feed(@current_user_id)
        expect(feed_after_unfollow["data"].select { |e| e["author_id"] == @celebrity_user_id.to_i }).to be_empty
      end
    end

    context "with multiple follows" do
      it "shows entries from all followed users in the feed" do
        # Check initial feed (should be empty as we've cleared follows)
        initial_feed = get_feed(@current_user_id)

        # Follow both users
        follow_user(@current_user_id, @regular_user_id)
        follow_user(@current_user_id, @celebrity_user_id)

        # Wait for Elasticsearch to process
        sleep(2)

        # Check feed - should contain entries from both users
        feed = get_feed(@current_user_id)
        expect(feed["data"].size).to be > 0

        # Verify entries are from both followed users
        regular_entries = feed["data"].select { |e| e["author_id"] == @regular_user_id.to_i }
        celebrity_entries = feed["data"].select { |e| e["author_id"] == @celebrity_user_id.to_i }

        expect(regular_entries.size).to be > 0
        expect(celebrity_entries.size).to be > 0

        # Clean up - unfollow both users
        unfollow_user(@current_user_id, @regular_user_id)
        unfollow_user(@current_user_id, @celebrity_user_id)
      end
    end
  end
end
