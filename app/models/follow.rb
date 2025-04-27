class Follow < ApplicationRecord
  belongs_to :user
  belongs_to :follower_user, class_name: 'User', foreign_key: 'follower_id'

  validates :user_id, presence: true
  validates :follower_id, presence: true
  validates :user_id, uniqueness: { scope: :follower_id }

  # Set a class variable to track whether we're inside a transaction
  # that should handle Kafka publishing
  thread_mattr_accessor :skip_kafka_callbacks

  # Normal callbacks that can be skipped when in a managed transaction
  after_create :publish_follow_created_event, unless: -> { Follow.skip_kafka_callbacks }
  after_destroy :publish_follow_deleted_event, unless: -> { Follow.skip_kafka_callbacks }

  scope :with_cursor_pagination, lambda { |cursor = nil, limit = 20|
    query = order(created_at: :desc, id: :desc)

    if cursor.present?
      cursor_data = decode_cursor(cursor)

      if cursor_data[:created_at].present? && cursor_data[:id].present?
        created_at = cursor_data[:created_at]
        id = cursor_data[:id]

        # Apply cursor conditions using 'where'
        # This handles "created_at = X AND id < Y" OR "created_at < X"
        query = query.where("(follows.created_at = ? AND follows.id < ?) OR follows.created_at < ?",
                          created_at, id, created_at)
      end
    end

    query.limit(limit)
  }

  def self.calculate_next_cursor(results, limit)
    return nil if results.empty? || results.size < limit

    last_record = results.last
    encode_cursor(created_at: last_record.created_at, id: last_record.id)
  end

  # Methods to explicitly publish events (useful for transaction handling)
  def publish_follow_created_event
    payload = {
      id: id,
      user_id: user_id,        # The user being followed
      follower_id: follower_id, # The user who is following
      created_at: created_at,
      event_type: 'follow_created'
    }

    result = Kafka::Producer.publish('follows', payload)
    unless result
      Rails.logger.error("Failed to publish follow #{id} creation event to Kafka")
    end
    result
  end

  def publish_follow_deleted_event
    payload = {
      id: id,
      user_id: user_id,        # The user being unfollowed
      follower_id: follower_id, # The user who is unfollowing
      event_type: 'follow_deleted'
    }

    result = Kafka::Producer.publish('follows', payload)
    unless result
      Rails.logger.error("Failed to publish follow #{id} deletion event to Kafka")
    end
    result
  end

  private

  def self.encode_cursor(data)
    Base64.strict_encode64(data.to_json)
  end

  def self.decode_cursor(cursor_string)
    begin
      JSON.parse(Base64.strict_decode64(cursor_string)).symbolize_keys
    rescue
      # If cursor is invalid, return empty hash which will be ignored
      {}
    end
  end
end
