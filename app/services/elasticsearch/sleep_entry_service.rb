module Elasticsearch
  class SleepEntryService
    class << self
      def create(sleep_entry)
        document = {
          id: sleep_entry.id,
          user_id: sleep_entry.user_id,
          sleep_entry_id: sleep_entry.id,
          sleep_duration: sleep_entry.sleep_duration,
          created_at: sleep_entry.created_at.iso8601,
          updated_at: sleep_entry.updated_at.iso8601
        }

        # Index the sleep entry in Elasticsearch
        ::Elasticsearch::Connection.index_document('sleep_entries', sleep_entry.id, document)

        # Also add to the feeds of all followers
        add_to_followers_feeds(sleep_entry)

        sleep_entry
      end

      def update(sleep_entry)
        document = {
          sleep_duration: sleep_entry.sleep_duration,
          updated_at: sleep_entry.updated_at.iso8601
        }

        # Update the sleep entry in Elasticsearch
        ::Elasticsearch::Connection.update_document('sleep_entries', sleep_entry.id, document)

        # Update the feeds of all followers
        update_followers_feeds(sleep_entry)

        sleep_entry
      end

      def delete(sleep_entry)
        # Delete from sleep entries index
        ::Elasticsearch::Connection.delete_document('sleep_entries', sleep_entry.id)

        # Delete from feeds index where sleep_entry_id matches
        delete_from_feeds(sleep_entry.id)

        sleep_entry
      end

      def find(id)
        result = ::Elasticsearch::Connection.get_document('sleep_entries', id)
        result.present? ? result['_source'] : nil
      end

      # Get sleep entries for a specific user
      def for_user(user_id, options = {})
        query = {
          query: {
            bool: {
              must: [
                { term: { user_id: user_id } }
              ]
            }
          },
          sort: [
            { created_at: { order: 'desc' } }
          ]
        }

        if options[:from_date].present?
          query[:query][:bool][:must] << {
            range: {
              created_at: {
                gte: options[:from_date].iso8601
              }
            }
          }
        end

        if options[:to_date].present?
          query[:query][:bool][:must] << {
            range: {
              created_at: {
                lte: options[:to_date].iso8601
              }
            }
          }
        end

        if options[:size].present?
          query[:size] = options[:size]
        end

        if options[:from].present?
          query[:from] = options[:from]
        end

        ::Elasticsearch::Connection.search('sleep_entries', query)
      end

      # Get feed items for a user (sleep entries of users they follow)
      def feed_for_user(user_id, options = {})
        query = {
          query: {
            bool: {
              must: [
                { term: { user_id: user_id } }
              ]
            }
          },
          sort: [
            { sleep_duration: { order: 'desc' } },  # Sort by sleep duration
            { created_at: { order: 'desc' } }       # Then by creation date
          ]
        }

        # Limit to previous week if specified
        if options[:previous_week] || options[:last_week]
          now = Time.current
          start_of_last_week = now.beginning_of_week - 1.week
          end_of_last_week = start_of_last_week.end_of_week

          query[:query][:bool][:must] << {
            range: {
              created_at: {
                gte: start_of_last_week.iso8601,
                lte: end_of_last_week.iso8601
              }
            }
          }
        elsif options[:from_date].present?
          query[:query][:bool][:must] << {
            range: {
              created_at: {
                gte: options[:from_date].iso8601
              }
            }
          }
        end

        if options[:to_date].present?
          query[:query][:bool][:must] << {
            range: {
              created_at: {
                lte: options[:to_date].iso8601
              }
            }
          }
        end

        if options[:size].present?
          query[:size] = options[:size]
        end

        if options[:from].present?
          query[:from] = options[:from]
        end

        ::Elasticsearch::Connection.search('feeds', query)
      end

      private

      def add_to_followers_feeds(sleep_entry)
        # Get all followers of the sleep entry owner
        followers = Follow.where(followed_id: sleep_entry.user_id)

        # Prepare bulk indexing data
        feed_documents = followers.map.with_index do |follow, index|
          {
            id: "#{sleep_entry.id}_#{follow.follower_id}",
            user_id: follow.follower_id,
            author_id: sleep_entry.user_id,
            sleep_entry_id: sleep_entry.id,
            sleep_duration: sleep_entry.sleep_duration,
            created_at: sleep_entry.created_at.iso8601,
            updated_at: sleep_entry.updated_at.iso8601
          }
        end

        # Bulk index into the feeds index if there are any followers
        if feed_documents.any?
          ::Elasticsearch::Connection.bulk_index('feeds', feed_documents)
        end
      end

      def update_followers_feeds(sleep_entry)
        # Get all followers of the sleep entry owner
        followers = Follow.where(followed_id: sleep_entry.user_id)

        # Update each follower's feed
        followers.each do |follow|
          document = {
            sleep_duration: sleep_entry.sleep_duration,
            updated_at: sleep_entry.updated_at.iso8601
          }

          ::Elasticsearch::Connection.update_document(
            'feeds',
            "#{sleep_entry.id}_#{follow.follower_id}",
            document
          )
        end
      end

      def delete_from_feeds(sleep_entry_id)
        # This would require a more complex solution in Elasticsearch
        # We would need to search for documents with the sleep_entry_id
        # and then delete them individually

        query = {
          query: {
            term: { sleep_entry_id: sleep_entry_id }
          },
          size: 10000 # Adjust based on your expected scale
        }

        results = ::Elasticsearch::Connection.search('feeds', query)

        if results['hits'] && results['hits']['hits'].any?
          results['hits']['hits'].each do |hit|
            ::Elasticsearch::Connection.delete_document('feeds', hit['_id'])
          end
        end
      end
    end
  end
end
