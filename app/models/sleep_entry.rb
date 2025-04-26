class SleepEntry < ApplicationRecord
  belongs_to :user

  validates :start_at, presence: true

  def sleep_duration
    ActiveSupport::Duration.build(self[:sleep_duration])
  end

  # Class methods for Elasticsearch integration
  class << self
    def search_by_user_id(user_id, options = {})
      ::Elasticsearch::SleepEntryService.for_user(user_id, options)
    end

    # Get feed for a user (sleep entries of users they follow)
    def feed_for_user(user_id, options = {})
      ::Elasticsearch::SleepEntryService.feed_for_user(user_id, options)
    end
  end
end
