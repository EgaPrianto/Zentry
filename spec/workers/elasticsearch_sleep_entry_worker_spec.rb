require 'rails_helper'

RSpec.describe ElasticsearchSleepEntryWorker do
  describe '.perform' do
    it 'subscribes to sleep_entries topic with correct consumer group' do
      expect(Kafka::Consumer).to receive(:consume)
        .with('sleep_entries', consumer_group: 'elasticsearch_indexer_sleep_entries')
        .and_yield({'event_type' => 'sleep_entry_created'})

      expect(described_class).to receive(:process_sleep_entry_message)
        .with({'event_type' => 'sleep_entry_created'})

      described_class.perform
    end
  end

  describe '.process_sleep_entry_message' do
    context 'when event_type is sleep_entry_created' do
      let(:message) { {'event_type' => 'sleep_entry_created', 'id' => 1} }

      it 'calls index_sleep_entry' do
        expect(described_class).to receive(:index_sleep_entry).with(message)
        described_class.send(:process_sleep_entry_message, message)
      end
    end

    context 'when event_type is sleep_entry_updated' do
      let(:message) { {'event_type' => 'sleep_entry_updated', 'id' => 1} }

      it 'calls update_sleep_entry' do
        expect(described_class).to receive(:update_sleep_entry).with(message)
        described_class.send(:process_sleep_entry_message, message)
      end
    end

    context 'when event_type is sleep_entry_deleted' do
      let(:message) { {'event_type' => 'sleep_entry_deleted', 'id' => 1} }

      it 'calls delete_sleep_entry' do
        expect(described_class).to receive(:delete_sleep_entry).with(message)
        described_class.send(:process_sleep_entry_message, message)
      end
    end

    context 'when event_type is unknown' do
      let(:message) { {'event_type' => 'unknown', 'id' => 1} }

      it 'logs an error' do
        expect(Rails.logger).to receive(:error).with("Unknown sleep entry event type: unknown")
        described_class.send(:process_sleep_entry_message, message)
      end
    end
  end

  describe '.index_sleep_entry' do
    let(:sleep_entry_id) { 123 }
    let(:user_id) { 456 }
    let(:sleep_duration) { 480 }
    let(:sleep_start_at) { "2025-04-29T22:00:00Z" }
    let(:created_at) { "2025-04-30T06:00:00Z" }
    let(:updated_at) { "2025-04-30T06:00:00Z" }

    let(:message) do
      {
        'id' => sleep_entry_id,
        'user_id' => user_id,
        'sleep_duration' => sleep_duration,
        'start_at' => sleep_start_at,
        'created_at' => created_at,
        'updated_at' => updated_at,
        'event_type' => 'sleep_entry_created'
      }
    end

    let(:expected_document) do
      {
        id: sleep_entry_id,
        user_id: user_id,
        sleep_entry_id: sleep_entry_id,
        sleep_duration: sleep_duration,
        sleep_start_at: sleep_start_at,
        created_at: created_at,
        updated_at: updated_at
      }
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end

    context 'when user is not a celebrity (fan-out approach)' do
      let(:follower_1) { instance_double(Follow, follower_id: 789) }
      let(:follower_2) { instance_double(Follow, follower_id: 790) }
      let(:followers) { [follower_1, follower_2] }

      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(false)
        allow(Follow).to receive(:where).with(user_id: user_id).and_return(followers)
      end

      it 'indexes the document in sleep_entries index' do
        expect(Elasticsearch::Connection).to receive(:index_document)
          .with('sleep_entries', sleep_entry_id, expected_document)

        described_class.send(:index_sleep_entry, message)
      end

      it 'also indexes in followers feeds using bulk_index' do
        expected_feed_documents = [
          {
            user_id: follower_1.follower_id,
            author_id: user_id,
            sleep_entry_id: sleep_entry_id,
            sleep_duration: sleep_duration,
            sleep_start_at: sleep_start_at,
            created_at: created_at,
            updated_at: updated_at
          },
          {
            user_id: follower_2.follower_id,
            author_id: user_id,
            sleep_entry_id: sleep_entry_id,
            sleep_duration: sleep_duration,
            sleep_start_at: sleep_start_at,
            created_at: created_at,
            updated_at: updated_at
          }
        ]

        expect(Elasticsearch::Connection).to receive(:index_document)
          .with('sleep_entries', sleep_entry_id, expected_document)
        expect(Elasticsearch::Connection).to receive(:bulk_index)
          .with('feeds', expected_feed_documents)

        described_class.send(:index_sleep_entry, message)
      end

      it 'logs success message' do
        allow(Elasticsearch::Connection).to receive(:index_document)
        allow(Elasticsearch::Connection).to receive(:bulk_index)

        expect(Rails.logger).to receive(:info).with("Successfully indexed sleep entry #{sleep_entry_id}")

        described_class.send(:index_sleep_entry, message)
      end
    end

    context 'when user is a celebrity (fan-in approach)' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(true)
      end

      it 'only indexes the document in sleep_entries index' do
        expect(Elasticsearch::Connection).to receive(:index_document)
          .with('sleep_entries', sleep_entry_id, expected_document)
        expect(Elasticsearch::Connection).not_to receive(:bulk_index)

        described_class.send(:index_sleep_entry, message)
      end
    end

    context 'when an error occurs' do
      before do
        allow(Elasticsearch::Connection).to receive(:index_document)
          .and_raise(StandardError.new("Test error"))
      end

      it 'catches the error and logs it' do
        expect(Rails.logger).to receive(:error).with("Error indexing sleep entry: Test error")
        expect(Rails.logger).to receive(:error).with(kind_of(String))

        described_class.send(:index_sleep_entry, message)
      end
    end
  end

  describe '.update_sleep_entry' do
    let(:sleep_entry_id) { 123 }
    let(:user_id) { 456 }
    let(:sleep_duration) { 500 }
    let(:sleep_start_at) { "2025-04-29T22:00:00Z" }
    let(:updated_at) { "2025-04-30T07:00:00Z" }

    let(:message) do
      {
        'id' => sleep_entry_id,
        'user_id' => user_id,
        'sleep_duration' => sleep_duration,
        'start_at' => sleep_start_at,
        'updated_at' => updated_at,
        'event_type' => 'sleep_entry_updated'
      }
    end

    let(:expected_document) do
      {
        sleep_duration: sleep_duration,
        sleep_start_at: sleep_start_at,
        updated_at: updated_at
      }
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end

    context 'when user is not a celebrity (fan-out approach)' do
      let(:follower_1) { instance_double(Follow, follower_id: 789) }
      let(:follower_2) { instance_double(Follow, follower_id: 790) }
      let(:followers) { [follower_1, follower_2] }

      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(false)
        allow(Follow).to receive(:where).with(user_id: user_id).and_return(followers)
      end

      it 'also updates each follower feed document' do
        expect(Elasticsearch::Connection).to receive(:update_document)
          .with('sleep_entries', sleep_entry_id, expected_document)

        expect(Elasticsearch::Connection).to receive(:update_document)
          .with('feeds', "#{sleep_entry_id}_#{follower_1.follower_id}", expected_document)
        expect(Elasticsearch::Connection).to receive(:update_document)
          .with('feeds', "#{sleep_entry_id}_#{follower_2.follower_id}", expected_document)

        described_class.send(:update_sleep_entry, message)
      end

      it 'logs success message' do
        allow(Elasticsearch::Connection).to receive(:update_document)

        expect(Rails.logger).to receive(:info).with("Successfully updated sleep entry #{sleep_entry_id}")

        described_class.send(:update_sleep_entry, message)
      end
    end

    context 'when user is a celebrity (fan-in approach)' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(true)
      end

      it 'only updates the document in sleep_entries index' do
        expect(Elasticsearch::Connection).to receive(:update_document)
          .with('sleep_entries', sleep_entry_id, expected_document)
        expect(Follow).not_to receive(:where)

        described_class.send(:update_sleep_entry, message)
      end
    end

    context 'when an error occurs' do
      before do
        allow(Elasticsearch::Connection).to receive(:update_document)
          .and_raise(StandardError.new("Test error"))
      end

      it 'catches the error and logs it' do
        expect(Rails.logger).to receive(:error).with("Error updating sleep entry: Test error")
        expect(Rails.logger).to receive(:error).with(kind_of(String))

        described_class.send(:update_sleep_entry, message)
      end
    end
  end

  describe '.delete_sleep_entry' do
    let(:sleep_entry_id) { 123 }
    let(:user_id) { 456 }

    let(:message) do
      {
        'id' => sleep_entry_id,
        'user_id' => user_id,
        'event_type' => 'sleep_entry_deleted'
      }
    end

    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end

    context 'when user is not a celebrity (fan-out approach)' do
      let(:search_results) do
        {
          'hits' => {
            'hits' => [
              {'_id' => "#{sleep_entry_id}_789"},
              {'_id' => "#{sleep_entry_id}_790"}
            ]
          }
        }
      end

      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(false)

        expected_query = {
          query: {
            term: { sleep_entry_id: sleep_entry_id }
          },
          size: 10000
        }

        allow(Elasticsearch::Connection).to receive(:search)
          .with('feeds', expected_query)
          .and_return(search_results)
      end

      it 'also deletes all related feed documents' do
        expect(Elasticsearch::Connection).to receive(:delete_document)
          .with('sleep_entries', sleep_entry_id)

        expect(Elasticsearch::Connection).to receive(:delete_document)
          .with('feeds', "#{sleep_entry_id}_789")
        expect(Elasticsearch::Connection).to receive(:delete_document)
          .with('feeds', "#{sleep_entry_id}_790")

        described_class.send(:delete_sleep_entry, message)
      end

      it 'logs success message' do
        allow(Elasticsearch::Connection).to receive(:delete_document)
        allow(Elasticsearch::Connection).to receive(:search).and_return(search_results)

        expect(Rails.logger).to receive(:info).with("Successfully deleted sleep entry #{sleep_entry_id}")

        described_class.send(:delete_sleep_entry, message)
      end
    end

    context 'when user is a celebrity (fan-in approach)' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(true)
      end

      it 'only deletes the document from sleep_entries index' do
        expect(Elasticsearch::Connection).to receive(:delete_document)
          .with('sleep_entries', sleep_entry_id)
        expect(Elasticsearch::Connection).not_to receive(:search)

        described_class.send(:delete_sleep_entry, message)
      end
    end

    context 'when an error occurs' do
      before do
        allow(Elasticsearch::Connection).to receive(:delete_document)
          .and_raise(StandardError.new("Test error"))
      end

      it 'catches the error and logs it' do
        expect(Rails.logger).to receive(:error).with("Error deleting sleep entry: Test error")
        expect(Rails.logger).to receive(:error).with(kind_of(String))

        described_class.send(:delete_sleep_entry, message)
      end
    end

    context 'when no feeds need to be deleted' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(false)

        empty_search_results = { 'hits' => { 'hits' => [] } }

        allow(Elasticsearch::Connection).to receive(:search).and_return(empty_search_results)
      end

      it 'still completes successfully' do
        expect(Elasticsearch::Connection).to receive(:delete_document)
          .with('sleep_entries', sleep_entry_id)

        expect(Elasticsearch::Connection).not_to receive(:delete_document)
          .with('feeds', anything)

        described_class.send(:delete_sleep_entry, message)
      end
    end
  end
end
