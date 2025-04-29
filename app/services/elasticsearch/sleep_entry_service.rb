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

        sleep_entry
      end

      def update(sleep_entry)
        document = {
          sleep_duration: sleep_entry.sleep_duration,
          updated_at: sleep_entry.updated_at.iso8601
        }

        # Update the sleep entry in Elasticsearch
        ::Elasticsearch::Connection.update_document('sleep_entries', sleep_entry.id, document)

        sleep_entry
      end

      def delete(sleep_entry)
        # Delete from sleep entries index
        ::Elasticsearch::Connection.delete_document('sleep_entries', sleep_entry.id)

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
        # Prepare the date range for filtering
        date_range = {}

        # Limit to previous week if specified
        if options[:previous_week] || options[:last_week]
          now = Time.current
          start_of_last_week = now.beginning_of_week - 1.week
          end_of_last_week = start_of_last_week.end_of_week

          date_range = {
            gte: start_of_last_week.iso8601,
            lte: end_of_last_week.iso8601
          }
        elsif options[:from_date].present?
          date_range[:gte] = options[:from_date].iso8601

          if options[:to_date].present?
            date_range[:lte] = options[:to_date].iso8601
          end
        end

        # Get result size and offset
        size = options[:size] || 10
        from = options[:from] || 0

        # We use a hybrid approach:
        # 1. For regular users (fan-out): Query the pre-computed feeds index
        # 2. For celebrity users (fan-in): Query sleep_entries directly at read time

        # First, get the list of celebrity users this person follows
        celebrity_ids = ::Elasticsearch::FeedStrategy.get_celebrity_following_ids(user_id)

        # Determine if we need fan-in, fan-out, or both
        if celebrity_ids.empty?
          # All followed users are regular - use pure fan-out approach
          return fan_out_feed_query(user_id, date_range, size, from)
        elsif ::Elasticsearch::FeedStrategy.get_regular_following_ids(user_id).empty?
          # All followed users are celebrities - use pure fan-in approach
          return fan_in_feed_query(user_id, celebrity_ids, date_range, size, from)
        else
          # Mixed case - need to combine results from fan-in and fan-out
          # We'll retrieve more results than needed and merge them
          combined_feed = combined_feed_query(user_id, celebrity_ids, date_range, size, from)
          return combined_feed
        end
      end

      private

      # Query feeds for regular users (fan-out approach)
      def fan_out_feed_query(user_id, date_range, size, from)
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
          ],
          size: size,
          from: from
        }

        # Add date range if specified
        if date_range.present?
          query[:query][:bool][:must] << {            range: { sleep_start_at: date_range }
          }
        end

        ::Elasticsearch::Connection.search('feeds', query)
      end

      # Query sleep_entries directly for celebrity users (fan-in approach)
      def fan_in_feed_query(user_id, celebrity_ids, date_range, size, from)
        query = {
          query: {
            bool: {
              must: [
                { terms: { user_id: celebrity_ids } }
              ]
            }
          },
          sort: [
            { sleep_duration: { order: 'desc' } },  # Sort by sleep duration
            { created_at: { order: 'desc' } }       # Then by creation date
          ],
          size: size,
          from: from
        }

        # Add date range if specified
        if date_range.present?
          query[:query][:bool][:must] << {

          range: { sleep_start_at: date_range }
          }
        end

        ::Elasticsearch::Connection.search('sleep_entries', query)
      end

      # Combined approach for users who follow both regular and celebrity users
      def combined_feed_query(user_id, celebrity_ids, date_range, size, from)
        # Get regular users' feed entries (fan-out)
        fan_out_results = fan_out_feed_query(user_id, date_range, size * 2, 0)

        # Get celebrity users' entries (fan-in)
        fan_in_results = fan_in_feed_query(user_id, celebrity_ids, date_range, size * 2, 0)

        # Combine and sort the results
        combined_hits = []

        # Extract hits from fan-out results
        if fan_out_results['hits'] && fan_out_results['hits']['hits'].present?
          combined_hits.concat(fan_out_results['hits']['hits'])
        end
        # Extract hits from fan-in results
        if fan_in_results['hits'] && fan_in_results['hits']['hits'].present?
          fan_in_results['hits']['hits'].each do |hit|
            # Rename user_id to author_id in the source document
            if hit['_source'] && hit['_source']['user_id']
              hit['_source']['author_id'] = hit['_source']['user_id'].to_i
              hit['_source']['user_id'] = user_id.to_i # set current user's ID
            end
            combined_hits << hit
          end
        end

        # Sort by sleep_duration (desc), then by created_at (desc)
        sorted_hits = combined_hits.sort_by do |hit|
          source = hit['_source']
          [-(source['sleep_duration'].to_i), -(Time.parse(source['created_at']).to_i)]
        end

        # Apply pagination
        paginated_hits = sorted_hits[from, size]

        # Format the response to match Elasticsearch's format
        {
          'hits' => {
            'total' => { 'value' => combined_hits.size, 'relation' => 'eq' },
            'hits' => paginated_hits || []
          }
        }
      end
    end
  end
end
