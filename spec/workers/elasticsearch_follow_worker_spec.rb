require 'rails_helper'

RSpec.describe ElasticsearchFollowWorker do
  describe '.perform' do
    it 'subscribes to follows topic with correct consumer group' do
      expect(Kafka::Consumer).to receive(:consume)
        .with('follows', consumer_group: 'elasticsearch_indexer_follows')
        .and_yield({'event_type' => 'follow_created'})
      
      expect(described_class).to receive(:process_follow_message)
        .with({'event_type' => 'follow_created'})
      
      described_class.perform
    end
  end
  
  describe '.process_follow_message' do
    context 'when event_type is follow_created' do
      let(:message) { {'event_type' => 'follow_created', 'user_id' => 1, 'follower_id' => 2} }
      
      it 'calls handle_new_follow' do
        expect(described_class).to receive(:handle_new_follow).with(message)
        described_class.send(:process_follow_message, message)
      end
    end
    
    context 'when event_type is follow_deleted' do
      let(:message) { {'event_type' => 'follow_deleted', 'user_id' => 1, 'follower_id' => 2} }
      
      it 'calls handle_unfollow' do
        expect(described_class).to receive(:handle_unfollow).with(message)
        described_class.send(:process_follow_message, message)
      end
    end
    
    context 'when event_type is unknown' do
      let(:message) { {'event_type' => 'unknown', 'user_id' => 1, 'follower_id' => 2} }
      
      it 'logs an error' do
        expect(Rails.logger).to receive(:error).with("Unknown follow event type: unknown")
        described_class.send(:process_follow_message, message)
      end
    end
  end
  
  describe '.handle_new_follow' do
    let(:user_id) { 123 }
    let(:follower_id) { 456 }
    
    let(:message) do
      {
        'user_id' => user_id,         # User being followed
        'follower_id' => follower_id, # User doing the following
        'event_type' => 'follow_created'
      }
    end
    
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end
    
    context 'when followed user is not a celebrity (fan-out approach)' do
      let(:sleep_entry_1) do
        instance_double(SleepEntry,
          id: 101,
          user_id: user_id,
          sleep_duration: 480,
          start_at: Time.new(2025, 4, 29, 22, 0, 0),
          created_at: Time.new(2025, 4, 30, 6, 0, 0),
          updated_at: Time.new(2025, 4, 30, 6, 0, 0)
        )
      end
      
      let(:sleep_entry_2) do
        instance_double(SleepEntry,
          id: 102,
          user_id: user_id,
          sleep_duration: 420,
          start_at: Time.new(2025, 4, 28, 23, 0, 0),
          created_at: Time.new(2025, 4, 29, 6, 0, 0),
          updated_at: Time.new(2025, 4, 29, 6, 0, 0)
        )
      end
      
      let(:sleep_entries) { [sleep_entry_1, sleep_entry_2] }
      
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(false)
        allow(SleepEntry).to receive(:where).with(user_id: user_id).and_return(sleep_entries)
      end
      
      it 'indexes followed user sleep entries in follower feed' do
        expected_feed_documents = [
          {
            id: "#{sleep_entry_1.id}_#{follower_id}",
            user_id: follower_id,
            author_id: user_id,
            sleep_entry_id: sleep_entry_1.id,
            sleep_duration: sleep_entry_1.sleep_duration,
            sleep_start_at: sleep_entry_1.start_at.iso8601,
            created_at: sleep_entry_1.created_at.iso8601,
            updated_at: sleep_entry_1.updated_at.iso8601
          },
          {
            id: "#{sleep_entry_2.id}_#{follower_id}",
            user_id: follower_id,
            author_id: user_id,
            sleep_entry_id: sleep_entry_2.id,
            sleep_duration: sleep_entry_2.sleep_duration,
            sleep_start_at: sleep_entry_2.start_at.iso8601,
            created_at: sleep_entry_2.created_at.iso8601,
            updated_at: sleep_entry_2.updated_at.iso8601
          }
        ]
        
        expect(Elasticsearch::Connection).to receive(:bulk_index)
          .with('feeds', expected_feed_documents)
        
        described_class.send(:handle_new_follow, message)
      end
      
      it 'logs success message' do
        allow(Elasticsearch::Connection).to receive(:bulk_index)
        
        expect(Rails.logger).to receive(:info).with("Successfully processed new follow relationship")
        
        described_class.send(:handle_new_follow, message)
      end
      
      context 'when followed user has no sleep entries' do
        before do
          allow(SleepEntry).to receive(:where).with(user_id: user_id).and_return([])
        end
        
        it 'does not call bulk_index' do
          expect(Elasticsearch::Connection).not_to receive(:bulk_index)
          
          described_class.send(:handle_new_follow, message)
        end
        
        it 'still logs success' do
          expect(Rails.logger).to receive(:info).with("Successfully processed new follow relationship")
          
          described_class.send(:handle_new_follow, message)
        end
      end
    end
    
    context 'when followed user is a celebrity (fan-in approach)' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(true)
      end
      
      it 'does not fetch sleep entries or index documents' do
        expect(SleepEntry).not_to receive(:where)
        expect(Elasticsearch::Connection).not_to receive(:bulk_index)
        
        described_class.send(:handle_new_follow, message)
      end
      
      it 'logs success message' do
        expect(Rails.logger).to receive(:info).with("Successfully processed new follow relationship")
        
        described_class.send(:handle_new_follow, message)
      end
    end
    
    context 'when an error occurs' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?)
          .with(user_id).and_raise(StandardError.new("Test error"))
      end
      
      it 'catches the error and logs it' do
        expect(Rails.logger).to receive(:error).with("Error handling new follow: Test error")
        expect(Rails.logger).to receive(:error).with(kind_of(String))
        
        described_class.send(:handle_new_follow, message)
      end
    end
  end
  
  describe '.handle_unfollow' do
    let(:user_id) { 123 }
    let(:follower_id) { 456 }
    
    let(:message) do
      {
        'user_id' => user_id,         # User being unfollowed
        'follower_id' => follower_id, # User doing the unfollowing
        'event_type' => 'follow_deleted'
      }
    end
    
    before do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
    end
    
    context 'when unfollowed user is not a celebrity (fan-out approach)' do
      let(:search_results) do
        {
          'hits' => {
            'hits' => [
              {'_id' => "101_#{follower_id}"},
              {'_id' => "102_#{follower_id}"}
            ]
          }
        }
      end
      
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(false)
        
        expected_query = {
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
        
        allow(Elasticsearch::Connection).to receive(:search)
          .with('feeds', expected_query)
          .and_return(search_results)
      end
      
      it 'removes followed user entries from follower feed' do
        expect(Elasticsearch::Connection).to receive(:delete_document)
          .with('feeds', "101_#{follower_id}")
        expect(Elasticsearch::Connection).to receive(:delete_document)
          .with('feeds', "102_#{follower_id}")
        
        described_class.send(:handle_unfollow, message)
      end
      
      it 'logs success message' do
        allow(Elasticsearch::Connection).to receive(:delete_document)
        allow(Elasticsearch::Connection).to receive(:search).and_return(search_results)
        
        expect(Rails.logger).to receive(:info).with("Successfully processed unfollow")
        
        described_class.send(:handle_unfollow, message)
      end
      
      context 'when no feed entries exist' do
        before do
          empty_search_results = { 'hits' => { 'hits' => [] } }
          
          allow(Elasticsearch::Connection).to receive(:search).and_return(empty_search_results)
        end
        
        it 'does not call delete_document' do
          expect(Elasticsearch::Connection).not_to receive(:delete_document)
          
          described_class.send(:handle_unfollow, message)
        end
        
        it 'still logs success' do
          expect(Rails.logger).to receive(:info).with("Successfully processed unfollow")
          
          described_class.send(:handle_unfollow, message)
        end
      end
    end
    
    context 'when unfollowed user is a celebrity (fan-in approach)' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?).with(user_id).and_return(true)
      end
      
      it 'does not search or delete documents' do
        expect(Elasticsearch::Connection).not_to receive(:search)
        expect(Elasticsearch::Connection).not_to receive(:delete_document)
        
        described_class.send(:handle_unfollow, message)
      end
      
      it 'logs success message' do
        expect(Rails.logger).to receive(:info).with("Successfully processed unfollow")
        
        described_class.send(:handle_unfollow, message)
      end
    end
    
    context 'when an error occurs' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:use_fan_in?)
          .with(user_id).and_raise(StandardError.new("Test error"))
      end
      
      it 'catches the error and logs it' do
        expect(Rails.logger).to receive(:error).with("Error handling unfollow: Test error")
        expect(Rails.logger).to receive(:error).with(kind_of(String))
        
        described_class.send(:handle_unfollow, message)
      end
    end
  end
end