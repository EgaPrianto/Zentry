class SleepEntryConsumerWorker
  def self.perform
    Kafka::Consumer.consume('sleep_entries') do |payload, key, message|
      Rails.logger.info("Processing sleep entry from Kafka: #{payload['id']}")

      # Process the sleep entry for storage in Cassandra
      store_in_cassandra(payload)

      # Process user feeds based on follower count
      process_feeds(payload['user_id'], payload['id'], payload['follower_count'])
    end
  end

  private

  def self.store_in_cassandra(payload)
    begin
      # Using the Cassandra SleepEntry model instead of the service
      sleep_entry_data = {
        id: payload['id'],
        sleep_entry_id: payload['id'],
        user_id: payload['user_id'],
        sleep_duration: payload['sleep_duration'],
        created_at: Time.parse(payload['created_at']),
        updated_at: Time.parse(payload['updated_at'])
      }

      Cassandra::SleepEntry.create!(sleep_entry_data)
      Rails.logger.info("Successfully stored sleep entry in Cassandra: #{payload['id']}")
    rescue => e
      puts ("Failed to store sleep entry in Cassandra: #{e.message}")
      puts (e.backtrace.join("\n"))
    end
  end

  def self.process_feeds(user_id, sleep_entry_id, follower_count)
    begin
      user = User.find_by(id: user_id)
      return unless user

      Rails.logger.info("Processing feed updates for sleep entry #{sleep_entry_id} by user #{user_id}")

      # Determine batch size based on follower count
      batch_size = [1000, (follower_count.to_i / 10).to_i].min
      batch_size = 100 if batch_size < 100

      # Process followers in batches
      (0..follower_count.to_i).step(batch_size) do |offset|
        followers_batch = user.followers.limit(batch_size).offset(offset).pluck(:follower_id)

        # Create feed entries in Cassandra for each follower using our model
        followers_batch.each do |follower_id|
          begin
            feed_data = {
              user_id: follower_id,
              author_id: user_id,
              sleep_entry_id: sleep_entry_id,
              created_at: Time.now.utc
            }

            Cassandra::Feed.create!(feed_data)
            Rails.logger.info("Created feed entry for follower #{follower_id}")
          rescue => e
            puts ("Failed to create feed entry for follower #{follower_id}: #{e.message}")
            # Continue processing other followers even if one fails
          end
        end
      end

      Rails.logger.info("Completed feed updates for sleep entry #{sleep_entry_id}")
    rescue => e
      puts ("Failed to process feeds for sleep entry #{sleep_entry_id}: #{e.message}")
      puts (e.backtrace.join("\n"))
    end
  end
end
