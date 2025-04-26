module Elasticsearch
  class IndexSetup
    class << self
      def setup_indices
        setup_sleep_entries_index
        setup_feeds_index
      end

      private

      def setup_sleep_entries_index
        Elasticsearch::Connection.create_index('sleep_entries', {
          properties: {
            id: { type: 'long' },
            user_id: { type: 'long' },
            sleep_entry_id: { type: 'long' },
            sleep_duration: { type: 'long' },
            created_at: { type: 'date' },
            updated_at: { type: 'date' }
          }
        })
      end

      def setup_feeds_index
        # This index is specifically designed for the feed feature
        # showing sleep records of a user's following connections
        Elasticsearch::Connection.create_index('feeds', {
          properties: {
            id: { type: 'long' },
            user_id: { type: 'long' },  # The user's feed
            author_id: { type: 'long' }, # The user who created the sleep entry
            sleep_entry_id: { type: 'long' },
            sleep_duration: { type: 'long' }, # Allows for sorting
            created_at: { type: 'date' },
            updated_at: { type: 'date' }
          }
        })
      end
    end
  end
end
