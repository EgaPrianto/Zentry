class Follow < ApplicationRecord
  belongs_to :user
  belongs_to :follower_user, class_name: 'User', foreign_key: 'follower_id'

  validates :user_id, presence: true
  validates :follower_id, presence: true
  validates :user_id, uniqueness: { scope: :follower_id }

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
