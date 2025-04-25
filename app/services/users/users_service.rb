module Users
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
  end
end
