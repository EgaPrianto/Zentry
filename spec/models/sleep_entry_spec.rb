require 'rails_helper'

RSpec.describe SleepEntry do
  subject(:sleep_entry) { build(:sleep_entry, user: user) }
  let(:user) { create(:user) }

  describe '#sleep_duration' do
    it 'returns an ActiveSupport::Duration object' do
      # Set a sleep duration in seconds (e.g., 8 hours)
      sleep_entry.sleep_duration = 28800
      sleep_entry.save!

      expect(sleep_entry.sleep_duration).to be_an(ActiveSupport::Duration)
      expect(sleep_entry.sleep_duration.to_i).to eq(28800)
    end
  end

  describe 'Kafka event publishing' do
    describe '#publish_created_event' do
      it 'publishes sleep entry creation to Kafka' do
        sleep_entry.save!

        expect(Kafka::Producer).to receive(:publish).with(
          'sleep_entries',
          hash_including(
            "id" => sleep_entry.id,
            "user_id" => user.id,
            "event_type" => 'sleep_entry_created'
          )
        ).and_return(true)

        expect(sleep_entry.publish_created_event).to be true
      end

      it 'logs error when publishing fails' do
        sleep_entry.save!

        expect(Kafka::Producer).to receive(:publish).and_return(false)
        expect(Rails.logger).to receive(:error).with("Failed to publish sleep entry #{sleep_entry.id} creation event to Kafka")

        expect(sleep_entry.publish_created_event).to be false
      end
    end

    describe '#publish_updated_event' do
      it 'publishes sleep entry update to Kafka' do
        sleep_entry.save!

        expect(Kafka::Producer).to receive(:publish).with(
          'sleep_entries',
          hash_including(
            "id" => sleep_entry.id,
            "user_id" => user.id,
            "event_type" => 'sleep_entry_updated',
            "follower_count" => 0
          )
        ).and_return(true)

        expect(sleep_entry.publish_updated_event).to be true
      end

      it 'logs error when publishing fails' do
        sleep_entry.save!

        expect(Kafka::Producer).to receive(:publish).and_return(false)
        expect(Rails.logger).to receive(:error).with("Failed to publish sleep entry #{sleep_entry.id} update event to Kafka")

        expect(sleep_entry.publish_updated_event).to be false
      end
    end

    describe '#publish_deleted_event' do
      it 'publishes sleep entry deletion to Kafka' do
        sleep_entry.save!

        expect(Kafka::Producer).to receive(:publish).with(
          'sleep_entries',
          hash_including(
            "id" => sleep_entry.id,
            "user_id" => user.id,
            "event_type" => 'sleep_entry_deleted'
          )
        ).and_return(true)

        expect(sleep_entry.publish_deleted_event).to be true
      end

      it 'logs error when publishing fails' do
        sleep_entry.save!

        expect(Kafka::Producer).to receive(:publish).and_return(false)
        expect(Rails.logger).to receive(:error).with("Failed to publish sleep entry #{sleep_entry.id} deletion event to Kafka")

        expect(sleep_entry.publish_deleted_event).to be false
      end
    end
  end

  describe 'class methods' do
    describe '.search_by_user_id' do
      it 'delegates to Elasticsearch::SleepEntryService.for_user' do
        options = { limit: 10 }

        expect(Elasticsearch::SleepEntryService).to receive(:for_user).with(user.id, options)

        described_class.search_by_user_id(user.id, options)
      end
    end

    describe '.feed_for_user' do
      it 'delegates to Elasticsearch::SleepEntryService.feed_for_user' do
        options = { limit: 10 }

        expect(Elasticsearch::SleepEntryService).to receive(:feed_for_user).with(user.id, options)

        described_class.feed_for_user(user.id, options)
      end
    end
  end

  describe 'callbacks' do
    context 'when skip_kafka_callbacks is false' do
      before do
        SleepEntry.skip_kafka_callbacks = false
      end

      it 'calls publish_created_event on create' do
        new_entry = build(:sleep_entry)
        expect(new_entry).to receive(:publish_created_event)
        new_entry.save!
      end

      it 'calls publish_updated_event on update' do
        sleep_entry.save!
        expect(sleep_entry).to receive(:publish_updated_event)
        sleep_entry.update!(start_at: sleep_entry.start_at + 1.hour)
      end

      it 'calls publish_deleted_event on destroy' do
        sleep_entry.save!
        expect(sleep_entry).to receive(:publish_deleted_event)
        sleep_entry.destroy
      end
    end

    context 'when skip_kafka_callbacks is true' do
      before do
        SleepEntry.skip_kafka_callbacks = true
      end

      after do
        SleepEntry.skip_kafka_callbacks = false
      end

      it 'does not call publish_created_event on create' do
        new_entry = build(:sleep_entry)
        expect(new_entry).not_to receive(:publish_created_event)
        new_entry.save!
      end

      it 'does not call publish_updated_event on update' do
        sleep_entry.save!
        expect(sleep_entry).not_to receive(:publish_updated_event)
        sleep_entry.update!(start_at: sleep_entry.start_at + 1.hour)
      end

      it 'does not call publish_deleted_event on destroy' do
        sleep_entry.save!
        expect(sleep_entry).not_to receive(:publish_deleted_event)
        sleep_entry.destroy
      end
    end
  end
end
