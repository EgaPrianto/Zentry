require 'rails_helper'

RSpec.describe SleepEntryService do
  describe '.create_sleep_entry' do
    let(:user) { create(:user) }
    let(:valid_params) do
      {
        wake_time: Time.current,
        sleep_time: Time.current - 8.hours
      }
    end
    let(:sleep_entry) { instance_double(SleepEntry, id: 1, user_id: user.id) }

    before do
      allow(SleepEntry).to receive(:new).and_return(sleep_entry)
      allow(sleep_entry).to receive(:save).and_return(true)
      allow(sleep_entry).to receive(:publish_created_event).and_return(true)
      allow(Rails.logger).to receive(:error)

      # Mock the transaction behavior
      allow(ActiveRecord::Base).to receive(:transaction).and_yield
    end

    context 'when successful' do
      it 'creates a sleep entry and publishes to Kafka' do
        expect(SleepEntry).to receive(:skip_kafka_callbacks=).with(true).ordered
        expect(sleep_entry).to receive(:save).and_return(true)
        expect(sleep_entry).to receive(:publish_created_event).and_return(true)
        expect(SleepEntry).to receive(:skip_kafka_callbacks=).with(false).ordered

        result = described_class.create_sleep_entry(user.id, valid_params)

        expect(result[:success]).to be true
        expect(result[:sleep_entry]).to eq sleep_entry
      end

      it 'creates the sleep entry with the merged user_id' do
        expect(SleepEntry).to receive(:new).with(valid_params.merge(user_id: user.id)).and_return(sleep_entry)

        described_class.create_sleep_entry(user.id, valid_params)
      end
    end

    context 'when save fails' do
      before do
        allow(sleep_entry).to receive(:save).and_return(false)
        allow(sleep_entry).to receive(:errors).and_return(double(full_messages: ['Sleep time must be before wake time']))
        # Don't actually raise Rollback in tests
        allow_any_instance_of(Object).to receive(:raise).with(ActiveRecord::Rollback)
      end

      it 'logs the error and returns failure result' do
        expect(Rails.logger).to receive(:error).with("Failed to save sleep entry: Sleep time must be before wake time")

        result = described_class.create_sleep_entry(user.id, valid_params)

        expect(result[:success]).to be false
        expect(result[:errors]).to eq sleep_entry.errors
      end
    end

    context 'when Kafka publishing fails' do
      before do
        allow(sleep_entry).to receive(:publish_created_event).and_return(false)
        # Don't actually raise Rollback in tests
        allow_any_instance_of(Object).to receive(:raise).with(ActiveRecord::Rollback)
      end

      it 'logs the error and returns failure result' do
        expect(Rails.logger).to receive(:error).with("Failed to publish sleep entry #{sleep_entry.id} to Kafka")

        result = described_class.create_sleep_entry(user.id, valid_params)

        expect(result[:success]).to be false
      end
    end

    context 'when an exception occurs' do
      before do
        allow(sleep_entry).to receive(:save).and_raise(StandardError.new('Test error'))
      end

      it 'logs the error and returns failure result' do
        expect(Rails.logger).to receive(:error).with("Error creating sleep entry: Test error")

        expect{ described_class.create_sleep_entry(user.id, valid_params) }.to raise_error(StandardError)
      end
    end

    it 'ensures Kafka callbacks are re-enabled even when exceptions occur' do
      # Simulate an unhandled exception
      allow(sleep_entry).to receive(:save).and_raise("Unexpected error")

      expect(SleepEntry).to receive(:skip_kafka_callbacks=).with(true)
      expect(SleepEntry).to receive(:skip_kafka_callbacks=).with(false)

      expect { described_class.create_sleep_entry(user.id, valid_params) }.to raise_error("ActiveRecord::Rollback")
    end
  end

  describe '.get_followers_feed' do
    let(:user_id) { 123 }
    let(:options) { { last_week: false, size: 5 } }
    let(:feed_result) { { sleep_entries: [{ id: 1 }] } }

    before do
      allow(Elasticsearch::SleepEntryService).to receive(:feed_for_user).and_return(feed_result)
    end

    it 'calls Elasticsearch::SleepEntryService.feed_for_user with default options' do
      expected_options = {
        last_week: true,
        size: 10,
        from: 0
      }

      expect(Elasticsearch::SleepEntryService).to receive(:feed_for_user).with(user_id, expected_options)

      described_class.get_followers_feed(user_id)
    end

    it 'calls Elasticsearch::SleepEntryService.feed_for_user with merged options' do
      expected_options = {
        last_week: false,
        size: 5,
        from: 0
      }

      expect(Elasticsearch::SleepEntryService).to receive(:feed_for_user).with(user_id, expected_options)

      described_class.get_followers_feed(user_id, options)
    end

    it 'returns the result from Elasticsearch::SleepEntryService.feed_for_user' do
      result = described_class.get_followers_feed(user_id)

      expect(result).to eq(feed_result)
    end
  end
end
