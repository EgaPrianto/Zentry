class Follow < ApplicationRecord
  belongs_to :user
  belongs_to :followed_user, class_name: 'User', foreign_key: 'follower_id'

  validates :user_id, presence: true
  validates :followed_user_id, presence: true
  validates :user_id, uniqueness: { scope: :followed_user_id }
end
