module Elasticsearch
  module FeedStrategy
    # Threshold after which we switch from fan-out to fan-in
    FOLLOWER_THRESHOLD = 10_000

    # Determine if a user should use fan-in or fan-out approach
    def self.use_fan_in?(user_id)
      # Get follower count
      follower_count = Follow.where(user_id: user_id).count
      follower_count >= FOLLOWER_THRESHOLD
    end

    # Get users that this user follows who are "celebrity" accounts
    def self.get_celebrity_following_ids(follower_id)
      # Find all users this person follows who have many followers
      celebrity_ids = []

      # Get all users that this person follows
      following_ids = Follow.where(follower_id: follower_id).pluck(:user_id)

      # For each followed user, check if they have many followers
      following_ids.each do |followed_id|
        follower_count = Follow.where(user_id: followed_id).count
        if follower_count >= FOLLOWER_THRESHOLD
          celebrity_ids << followed_id
        end
      end

      celebrity_ids
    end

    # Get users that this user follows who are regular accounts
    def self.get_regular_following_ids(follower_id)
      # Find all users this person follows who don't have many followers
      following_ids = Follow.where(follower_id: follower_id).pluck(:user_id)
      celebrity_ids = get_celebrity_following_ids(follower_id)

      following_ids - celebrity_ids
    end
  end
end
