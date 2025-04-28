class SleepEntry < ApplicationRecord
  belongs_to :user

  validates :start_at, presence: true

  # Set a class variable to track whether we're inside a transaction
  # that should handle Kafka publishing
  thread_mattr_accessor :skip_kafka_callbacks

  # Normal callbacks that can be skipped when in a managed transaction
  after_create :publish_created_event, unless: -> { SleepEntry.skip_kafka_callbacks }
  after_update :publish_updated_event, unless: -> { SleepEntry.skip_kafka_callbacks }
  after_destroy :publish_deleted_event, unless: -> { SleepEntry.skip_kafka_callbacks }

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

  # Methods to explicitly publish events (useful for transaction handling)
  def publish_created_event
    kafka_payload = self.as_json
    kafka_payload["follower_count"] = self.user&.followers&.count || 0
    kafka_payload["event_type"] = 'sleep_entry_created'

    result = Kafka::Producer.publish('sleep_entries', kafka_payload)
    unless result
      Rails.logger.error("Failed to publish sleep entry #{id} creation event to Kafka")
    end
    result
  end

  def publish_updated_event
    kafka_payload = self.as_json
    kafka_payload["follower_count"] = self.user&.followers&.count || 0
    kafka_payload["event_type"] = 'sleep_entry_updated'

    result = Kafka::Producer.publish('sleep_entries', kafka_payload)
    unless result
      Rails.logger.error("Failed to publish sleep entry #{id} update event to Kafka")
    end
    result
  end

  def publish_deleted_event
    kafka_payload = {
      "id" => id,
      "user_id" => user_id,
      "event_type" => 'sleep_entry_deleted'
    }

    result = Kafka::Producer.publish('sleep_entries', kafka_payload)
    unless result
      Rails.logger.error("Failed to publish sleep entry #{id} deletion event to Kafka")
    end
    result
  end
end
