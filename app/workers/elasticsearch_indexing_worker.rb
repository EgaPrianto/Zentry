class ElasticsearchIndexingWorker
  def self.perform
    Rails.logger.info("Starting ElasticsearchIndexingWorker")

    # Subscribe to sleep entries topic
    Kafka::Consumer.subscribe('sleep_entries', 'elasticsearch_indexer_group') do |message|
      process_sleep_entry_message(message)
    end

    # Subscribe to follows topic
    Kafka::Consumer.subscribe('follows', 'elasticsearch_indexer_group') do |message|
      process_follow_message(message)
    end
  end

  private

  def self.process_sleep_entry_message(message)
    Rails.logger.info("Processing sleep entry message: #{message['event_type']}")

    case message['event_type']
    when 'sleep_entry_created'
      index_sleep_entry(message)
    when 'sleep_entry_updated'
      update_sleep_entry(message)
    when 'sleep_entry_deleted'
      delete_sleep_entry(message)
    else
      Rails.logger.error("Unknown sleep entry event type: #{message['event_type']}")
    end
  end

  def self.process_follow_message(message)
    Rails.logger.info("Processing follow message: #{message['event_type']}")

    case message['event_type']
    when 'follow_created'
      handle_new_follow(message)
    when 'follow_deleted'
      handle_unfollow(message)
    else
      Rails.logger.error("Unknown follow event type: #{message['event_type']}")
    end
  end

  # Sleep entry operations

  def self.index_sleep_entry(message)
    begin
      sleep_entry_id = message['id']
      user_id = message['user_id']
      sleep_duration = message['sleep_duration'].to_i
      created_at = message['created_at']
      updated_at = message['updated_at']

      # Always index the sleep entry in the main sleep_entries index
      document = {
        id: sleep_entry_id,
        user_id: user_id,
        sleep_entry_id: sleep_entry_id,
        sleep_duration: sleep_duration,
        created_at: created_at,
        updated_at: updated_at
      }

      Elasticsearch::Connection.index_document('sleep_entries', sleep_entry_id, document)

      # Check if this user is a "celebrity" (many followers)
      # If yes, we don't fan-out to all followers to avoid write amplification
      unless Elasticsearch::FeedStrategy.use_fan_in?(user_id)
        # Add to followers' feeds using fan-out approach (for users with reasonable follower count)
        followers = Follow.where(user_id: user_id)

        feed_documents = followers.map do |follow|
          {
            id: "#{sleep_entry_id}_#{follow.follower_id}",
            user_id: follow.follower_id,
            author_id: user_id,
            sleep_entry_id: sleep_entry_id,
            sleep_duration: sleep_duration,
            created_at: created_at,
            updated_at: updated_at
          }
        end

        if feed_documents.any?
          Elasticsearch::Connection.bulk_index('feeds', feed_documents)
        end
      end

      Rails.logger.info("Successfully indexed sleep entry #{sleep_entry_id}")
    rescue => e
      Rails.logger.error("Error indexing sleep entry: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end

  def self.update_sleep_entry(message)
    begin
      sleep_entry_id = message['id']
      user_id = message['user_id']
      sleep_duration = message['sleep_duration'].to_i
      updated_at = message['updated_at']

      # Update the sleep entry document
      document = {
        sleep_duration: sleep_duration,
        updated_at: updated_at
      }

      Elasticsearch::Connection.update_document('sleep_entries', sleep_entry_id, document)

      # Only update fan-out entries for non-celebrity users
      unless Elasticsearch::FeedStrategy.use_fan_in?(user_id)
        # Update in followers' feeds
        followers = Follow.where(user_id: user_id)

        followers.each do |follow|
          feed_id = "#{sleep_entry_id}_#{follow.follower_id}"
          Elasticsearch::Connection.update_document('feeds', feed_id, document)
        end
      end

      Rails.logger.info("Successfully updated sleep entry #{sleep_entry_id}")
    rescue => e
      Rails.logger.error("Error updating sleep entry: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end

  def self.delete_sleep_entry(message)
    begin
      sleep_entry_id = message['id']
      user_id = message['user_id']

      # Delete the sleep entry document
      Elasticsearch::Connection.delete_document('sleep_entries', sleep_entry_id)

      # Only delete fan-out entries for non-celebrity users
      unless Elasticsearch::FeedStrategy.use_fan_in?(user_id)
        # Delete from feeds
        query = {
          query: {
            term: { sleep_entry_id: sleep_entry_id }
          },
          size: 10000
        }

        results = Elasticsearch::Connection.search('feeds', query)

        if results['hits'] && results['hits']['hits'].any?
          results['hits']['hits'].each do |hit|
            Elasticsearch::Connection.delete_document('feeds', hit['_id'])
          end
        end
      end

      Rails.logger.info("Successfully deleted sleep entry #{sleep_entry_id}")
    rescue => e
      Rails.logger.error("Error deleting sleep entry: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end

  # Follow operations

  def self.handle_new_follow(message)
    begin
      user_id = message['user_id']        # The user being followed
      follower_id = message['follower_id'] # The user who is following

      # Only fan-out for non-celebrity users
      # If the user being followed is a celebrity, don't copy their entries to follower's feed
      unless Elasticsearch::FeedStrategy.use_fan_in?(user_id)
        # When user A follows user B, add all of user B's sleep entries to user A's feed
        sleep_entries = SleepEntry.where(user_id: user_id)

        feed_documents = sleep_entries.map do |sleep_entry|
          {
            id: "#{sleep_entry.id}_#{follower_id}",
            user_id: follower_id,
            author_id: user_id,
            sleep_entry_id: sleep_entry.id,
            sleep_duration: sleep_entry.sleep_duration.to_i,
            created_at: sleep_entry.created_at.iso8601,
            updated_at: sleep_entry.updated_at.iso8601
          }
        end

        if feed_documents.any?
          Elasticsearch::Connection.bulk_index('feeds', feed_documents)
        end
      end

      Rails.logger.info("Successfully processed new follow relationship")
    rescue => e
      Rails.logger.error("Error handling new follow: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end

  def self.handle_unfollow(message)
    begin
      user_id = message['user_id']        # The user being unfollowed
      follower_id = message['follower_id'] # The user who is unfollowing

      # Only need to remove entries for non-celebrity accounts
      # For celebrity accounts, we don't fan-out so there's nothing to remove
      unless Elasticsearch::FeedStrategy.use_fan_in?(user_id)
        query = {
          query: {
            bool: {
              must: [
                { term: { user_id: follower_id } },
                { term: { author_id: user_id } }
              ]
            }
          },
          size: 10000
        }

        results = Elasticsearch::Connection.search('feeds', query)

        if results['hits'] && results['hits']['hits'].any?
          results['hits']['hits'].each do |hit|
            Elasticsearch::Connection.delete_document('feeds', hit['_id'])
          end
        end
      end

      Rails.logger.info("Successfully processed unfollow")
    rescue => e
      Rails.logger.error("Error handling unfollow: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end
end
