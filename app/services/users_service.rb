class UsersService
  attr_reader :user_id, :limit, :cursor

  def initialize(user_id, limit: 20, cursor: nil)
    @user_id = user_id
    @limit = [limit.to_i, 100].min # Limit maximum per page to 100
    @limit = 20 if @limit < 1
    @cursor = cursor
  end

  # Get users who follow the specified user
  def list_followers
    user = User.find_by(id: user_id)
    return { success: false, error: 'User not found' } unless user
    # Use the model's scope for cursor-based pagination
    followers_with_cursor = user.followers.includes(:follower_user).with_cursor_pagination(cursor, limit)

    # Calculate next cursor using the model's method
    next_cursor = Follow.calculate_next_cursor(followers_with_cursor, limit)

    {
      success: true,
      followers: followers_with_cursor.map(&:follower_user),
      pagination: {
        limit: limit,
        next_cursor: next_cursor
      }
    }
  end

  # Get users that the specified user follows
  def list_following
    user = User.find_by(id: user_id)
    return { success: false, error: 'User not found' } unless user

    # Use the model's scope for cursor-based pagination
    following_with_cursor = user.follows.includes(:user).with_cursor_pagination(cursor, limit)

    # Calculate next cursor using the model's method
    next_cursor = Follow.calculate_next_cursor(following_with_cursor, limit)

    {
      success: true,
      following: following_with_cursor.map(&:user),
      pagination: {
        limit: limit,
        next_cursor: next_cursor
      }
    }
  end

  # Create a follow relationship with transaction to ensure Kafka event publishing
  def self.create_follow(follower_id, user_id)
    result = { success: false }

    ActiveRecord::Base.transaction do
      begin
        # Disable automatic callbacks
        Follow.skip_kafka_callbacks = true

        follow = Follow.new(user_id: user_id, follower_id: follower_id)

        if follow.save
          # Explicitly publish to Kafka within the transaction
          if follow.publish_follow_created_event
            result = { success: true, follow: follow }
          else
            result = { success: false, error: "Failed to publish to Kafka" }
            raise ActiveRecord::Rollback
          end
        else
          result = { success: false, error: follow.errors.full_messages.join(", ") }
          raise ActiveRecord::Rollback
        end
      rescue => e
        Rails.logger.error("Error creating follow: #{e.message}")
        result = { success: false, error: e.message }
        raise ActiveRecord::Rollback
      ensure
        # Re-enable automatic callbacks
        Follow.skip_kafka_callbacks = false
      end
    end

    result
  end

  # Destroy a follow relationship with transaction to ensure Kafka event publishing
  def self.destroy_follow(follow)
    result = { success: false }

    ActiveRecord::Base.transaction do
      begin
        # Disable automatic callbacks
        Follow.skip_kafka_callbacks = true

        # Store the follow information before destroying it
        follow_id = follow.id
        user_id = follow.user_id
        follower_id = follow.follower_id

        if follow.destroy
          # Create a temporary follow object to publish the event
          temp_follow = Follow.new(id: follow_id, user_id: user_id, follower_id: follower_id)

          # Explicitly publish to Kafka within the transaction
          if temp_follow.publish_follow_deleted_event
            result = { success: true }
          else
            result = { success: false, error: "Failed to publish to Kafka" }
            raise ActiveRecord::Rollback
          end
        else
          result = { success: false, error: follow.errors.full_messages.join(", ") }
          raise ActiveRecord::Rollback
        end
      rescue => e
        Rails.logger.error("Error destroying follow: #{e.message}")
        result = { success: false, error: e.message }
        raise ActiveRecord::Rollback
      ensure
        # Re-enable automatic callbacks
        Follow.skip_kafka_callbacks = false
      end
    end

    result
  end
end
