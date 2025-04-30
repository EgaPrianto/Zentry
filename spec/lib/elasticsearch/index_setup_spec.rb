require 'rails_helper'

RSpec.describe Elasticsearch::IndexSetup do
  describe '.setup_indices' do
    it 'sets up both required indices' do
      expect(described_class).to receive(:setup_sleep_entries_index)
      expect(described_class).to receive(:setup_feeds_index)

      described_class.setup_indices
    end
  end

  describe '.setup_sleep_entries_index' do
    let(:expected_mappings) do
      {
        properties: {
          id: { type: 'long' },
          user_id: { type: 'long' },
          sleep_entry_id: { type: 'long' },
          sleep_duration: { type: 'long' },
          sleep_start_at: { type: 'date' },
          created_at: { type: 'date' },
          updated_at: { type: 'date' }
        }
      }
    end

    it 'creates the sleep_entries index with correct mappings' do
      expect(Elasticsearch::Connection).to receive(:create_index)
        .with('sleep_entries', expected_mappings)

      described_class.send(:setup_sleep_entries_index)
    end
  end

  describe '.setup_feeds_index' do
    let(:expected_mappings) do
      {
        properties: {
          user_id: { type: 'long' },
          author_id: { type: 'long' },
          sleep_entry_id: { type: 'long' },
          sleep_duration: { type: 'long' },
          sleep_start_at: { type: 'date' },
          created_at: { type: 'date' },
          updated_at: { type: 'date' }
        }
      }
    end

    it 'creates the feeds index with correct mappings' do
      expect(Elasticsearch::Connection).to receive(:create_index)
        .with('feeds', expected_mappings)

      described_class.send(:setup_feeds_index)
    end
  end
end
