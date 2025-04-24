class User < ApplicationRecord
  has_many :sleep_entries, dependent: :destroy

  # Users that this user follows
  has_many :follows, foreign_key: :follower_id, dependent: :destroy
  has_many :followed_users, through: :follows, source: :user

  # Users following this user (followers)
  has_many :followers, class_name: 'Follow', foreign_key: :user_id, dependent: :destroy
  has_many :follower_users, through: :followers, source: :followed_user
end
