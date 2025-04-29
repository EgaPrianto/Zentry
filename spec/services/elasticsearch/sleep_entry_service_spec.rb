require 'rails_helper'

RSpec.describe Elasticsearch::SleepEntryService do
  describe '#create' do
    let(:sleep_entry) { instance_double(SleepEntry, id: 1, user_id: 2, sleep_duration: 480, created_at: Time.current, updated_at: Time.current) }

    it 'indexes a document in elasticsearch' do
      expected_document = {
        id: sleep_entry.id,
        user_id: sleep_entry.user_id,
        sleep_entry_id: sleep_entry.id,
        sleep_duration: sleep_entry.sleep_duration,
        created_at: sleep_entry.created_at.iso8601,
        updated_at: sleep_entry.updated_at.iso8601
      }

      expect(Elasticsearch::Connection).to receive(:index_document)
        .with('sleep_entries', sleep_entry.id, expected_document)

      result = described_class.create(sleep_entry)
      expect(result).to eq(sleep_entry)
    end
  end

  describe '#update' do
    let(:sleep_entry) { instance_double(SleepEntry, id: 1, sleep_duration: 480, updated_at: Time.current) }

    it 'updates a document in elasticsearch' do
      expected_document = {
        sleep_duration: sleep_entry.sleep_duration,
        updated_at: sleep_entry.updated_at.iso8601
      }

      expect(Elasticsearch::Connection).to receive(:update_document)
        .with('sleep_entries', sleep_entry.id, expected_document)

      result = described_class.update(sleep_entry)
      expect(result).to eq(sleep_entry)
    end
  end

  describe '#delete' do
    let(:sleep_entry) { instance_double(SleepEntry, id: 1) }

    it 'deletes a document from elasticsearch' do
      expect(Elasticsearch::Connection).to receive(:delete_document)
        .with('sleep_entries', sleep_entry.id)

      result = described_class.delete(sleep_entry)
      expect(result).to eq(sleep_entry)
    end
  end

  describe '#find' do
    let(:id) { 1 }
    let(:source) { { 'id' => id, 'user_id' => 2, 'sleep_duration' => 480 } }
    let(:es_response) { { '_source' => source } }

    it 'retrieves a document from elasticsearch' do
      expect(Elasticsearch::Connection).to receive(:get_document)
        .with('sleep_entries', id)
        .and_return(es_response)

      result = described_class.find(id)
      expect(result).to eq(source)
    end

    it 'returns nil when document is not found' do
      expect(Elasticsearch::Connection).to receive(:get_document)
        .with('sleep_entries', id)
        .and_return(nil)

      result = described_class.find(id)
      expect(result).to be_nil
    end
  end

  describe '#for_user' do
    let(:user_id) { 1 }
    let(:es_response) { { 'hits' => { 'hits' => [] } } }

    it 'queries elasticsearch with the correct parameters' do
      expected_query = {
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

      expect(Elasticsearch::Connection).to receive(:search)
        .with('sleep_entries', expected_query)
        .and_return(es_response)

      described_class.for_user(user_id)
    end

    it 'handles additional query parameters' do
      from_date = Time.current - 1.week
      to_date = Time.current
      size = 5
      from = 10

      options = {
        from_date: from_date,
        to_date: to_date,
        size: size,
        from: from
      }

      expected_query = {
        query: {
          bool: {
            must: [
              { term: { user_id: user_id } },
              { range: { created_at: { gte: from_date.iso8601 } } },
              { range: { created_at: { lte: to_date.iso8601 } } }
            ]
          }
        },
        sort: [
          { created_at: { order: 'desc' } }
        ],
        size: size,
        from: from
      }

      expect(Elasticsearch::Connection).to receive(:search)
        .with('sleep_entries', expected_query)
        .and_return(es_response)

      described_class.for_user(user_id, options)
    end
  end

  describe '#feed_for_user' do
    let(:user_id) { 1 }
    let(:size) { 10 }
    let(:from) { 0 }
    let(:options) { { size: size, from: from } }

    context 'when user only follows regular users' do
      before do
        allow(Elasticsearch::FeedStrategy).to receive(:get_celebrity_following_ids)
          .with(user_id)
          .and_return([])
      end

      it 'uses fan-out approach' do
        expected_query = {
          query: {
            bool: {
              must: [
                { term: { user_id: user_id } }
              ]
            }
          },
          sort: [
            { sleep_duration: { order: 'desc' } },
            { created_at: { order: 'desc' } }
          ],
          size: size,
          from: from
        }

        expect(Elasticsearch::Connection).to receive(:search)
          .with('feeds', expected_query)
          .and_return({ 'hits' => { 'hits' => [] } })

        described_class.feed_for_user(user_id, options)
      end
    end

    context 'when user only follows celebrity users' do
      let(:celebrity_ids) { [101, 102] }

      before do
        allow(Elasticsearch::FeedStrategy).to receive(:get_celebrity_following_ids)
          .with(user_id)
          .and_return(celebrity_ids)

        allow(Elasticsearch::FeedStrategy).to receive(:get_regular_following_ids)
          .with(user_id)
          .and_return([])
      end

      it 'uses fan-in approach' do
        expected_query = {
          query: {
            bool: {
              must: [
                { terms: { user_id: celebrity_ids } }
              ]
            }
          },
          sort: [
            { sleep_duration: { order: 'desc' } },
            { created_at: { order: 'desc' } }
          ],
          size: size,
          from: from
        }

        mock_response = {
          'hits' => {
            'hits' => [
              {
                '_source' => {
                  'user_id' => celebrity_ids[0],
                  'sleep_duration' => 480,
                  'created_at' => '2025-04-29T00:00:00Z'
                }
              }
            ]
          }
        }

        expect(Elasticsearch::Connection).to receive(:search)
          .with('sleep_entries', expected_query)
          .and_return(mock_response)

        result = described_class.feed_for_user(user_id, options)

        # Check that user_id is transformed properly
        transformed_hit = result['hits']['hits'][0]['_source']
        expect(transformed_hit['author_id']).to eq(celebrity_ids[0])
        expect(transformed_hit['user_id']).to eq(user_id)
      end
    end

    context 'when user follows both regular and celebrity users' do
      let(:celebrity_ids) { [101, 102] }

      before do
        allow(Elasticsearch::FeedStrategy).to receive(:get_celebrity_following_ids)
          .with(user_id)
          .and_return(celebrity_ids)

        allow(Elasticsearch::FeedStrategy).to receive(:get_regular_following_ids)
          .with(user_id)
          .and_return([201, 202])
      end

      it 'uses combined approach with both fan-in and fan-out' do
        # Mock fan-out results
        fan_out_results = {
          'hits' => {
            'hits' => [
              {
                '_source' => {
                  'user_id' => user_id,
                  'author_id' => 201,
                  'sleep_duration' => 480,
                  'created_at' => '2025-04-29T00:00:00Z'
                }
              }
            ]
          }
        }

        # Mock fan-in results
        fan_in_results = {
          'hits' => {
            'hits' => [
              {
                '_source' => {
                  'user_id' => celebrity_ids[0],
                  'sleep_duration' => 500,
                  'created_at' => '2025-04-29T01:00:00Z'
                }
              }
            ]
          }
        }

        # Expected transformed fan-in results after processing
        expected_transformed_fan_in = {
          'hits' => {
            'hits' => [
              {
                '_source' => {
                  'author_id' => celebrity_ids[0],
                  'user_id' => user_id,
                  'sleep_duration' => 500,
                  'created_at' => '2025-04-29T01:00:00Z'
                }
              }
            ]
          }
        }

        expect(described_class).to receive(:fan_out_feed_query)
          .with(user_id, anything, size * 2, 0)
          .and_return(fan_out_results)

        expect(described_class).to receive(:fan_in_feed_query)
          .with(user_id, celebrity_ids, anything, size * 2, 0)
          .and_return(expected_transformed_fan_in)

        result = described_class.feed_for_user(user_id, options)

        # Combined feed should have properly sorted entries
        expect(result['hits']['total']['value']).to eq(2)
        expect(result['hits']['hits'].size).to eq(2)

        # Sleep entries should be sorted by sleep duration (desc)
        first_entry = result['hits']['hits'][0]['_source']
        second_entry = result['hits']['hits'][1]['_source']
        expect(first_entry['sleep_duration']).to be > second_entry['sleep_duration']
      end
    end
  end
end
