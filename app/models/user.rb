class User < ApplicationRecord
  has_many :sleep_entries, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :followed_users, through: :follows, source: :followed_user

  validates :username, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true
  validates :password, presence: true

end
