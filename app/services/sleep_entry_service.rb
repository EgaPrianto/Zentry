class SleepEntryService
  def self.create_sleep_entry(user_id, params)
    result = { success: false }

    # Start a database transaction
    ActiveRecord::Base.transaction do
      begin
        # Create the sleep entry
        sleep_entry = SleepEntry.new(params.merge(user_id: user_id))
        if sleep_entry.save
          # Publish to Kafka for further processing
          # Include event_type for Elasticsearch consumer to process
          kafka_payload = sleep_entry.as_json.merge(
            follower_count: User.find(user_id).followers.count,
            event_type: 'sleep_entry_created'
          )

          unless Kafka::Producer.publish('sleep_entries', kafka_payload)
            Rails.logger.error("Failed to publish sleep entry #{sleep_entry.id} to Kafka")
            # Rollback the transaction if Kafka publishing fails
            raise ActiveRecord::Rollback
          end

          result = { success: true, sleep_entry: sleep_entry }
        else
          Rails.logger.error("Failed to save sleep entry: #{sleep_entry.errors.full_messages.join(', ')}")
          result = { success: false, errors: sleep_entry.errors }
          raise ActiveRecord::Rollback
        end
      rescue => e
        Rails.logger.error("Error creating sleep entry: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        result = { success: false, errors: { base: [e.message] } }
        raise ActiveRecord::Rollback
      end
    end

    result
  end

  def self.get_followers_feed(user_id, options = {})
    # Default options
    default_options = {
      last_week: true,
      size: 10,
      from: 0
    }

    # Merge with provided options
    options = default_options.merge(options)

    # Use our Elasticsearch service to get feed data
    Elasticsearch::SleepEntryService.feed_for_user(user_id, options)
  end
end
