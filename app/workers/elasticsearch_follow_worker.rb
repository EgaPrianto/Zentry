class ElasticsearchFollowWorker
  def self.perform
    Rails.logger.info("Starting ElasticsearchFollowWorker")

    # Subscribe to follows topic
    Kafka::Consumer.consume('follows', consumer_group: 'elasticsearch_indexer_follows') do |message|
      process_follow_message(message)
    end
  end

  private

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
            sleep_start_at: sleep_entry.start_at.iso8601,
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
