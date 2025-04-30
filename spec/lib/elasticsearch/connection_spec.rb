require 'rails_helper'

RSpec.describe Elasticsearch::Connection do
  let(:mock_client) { double("Elasticsearch::Client") }
  let(:mock_indices_client) { double("Elasticsearch::API::Indices::IndicesClient") }
  let(:index_name) { 'test_index' }
  let(:document_id) { 123 }
  let(:document) { { id: document_id, title: 'Test Document', content: 'Testing' } }

  before do
    allow(Elasticsearch::Client).to receive(:new).and_return(mock_client)

    # In new versions of Elasticsearch gem, the indices API is accessed differently
    # Use this approach to support both older and newer versions
    allow(mock_client).to receive(:indices).and_return(mock_indices_client)

    # Reset the client before each test
    described_class.instance_variable_set(:@client, nil)
  end

  describe '.client' do
    it 'creates an Elasticsearch client' do
      expect(Elasticsearch::Client).to receive(:new).and_return(mock_client)
      expect(described_class.client).to eq(mock_client)
    end

    it 'caches the client' do
      expect(Elasticsearch::Client).to receive(:new).once.and_return(mock_client)
      2.times { described_class.client }
    end
  end

  describe '.index_exists?' do
    it 'checks if an index exists' do
      # Use exists? with question mark to match the actual implementation
      expect(mock_indices_client).to receive(:exists?).with(index: index_name).and_return(true)
      expect(described_class.index_exists?(index_name)).to be true
    end
  end

  describe '.create_index' do
    context 'when index does not exist' do
      before do
        allow(described_class).to receive(:index_exists?).and_return(false)
      end

      it 'creates a new index with default settings' do
        expect(mock_indices_client).to receive(:create).with(
          index: index_name,
          body: {
            settings: {
              number_of_shards: 1,
              number_of_replicas: 0
            },
            mappings: {}
          }
        )
        described_class.create_index(index_name)
      end

      it 'creates a new index with custom mappings' do
        mappings = {
          properties: {
            title: { type: 'text' },
            content: { type: 'text' }
          }
        }

        expect(mock_indices_client).to receive(:create).with(
          index: index_name,
          body: {
            settings: {
              number_of_shards: 1,
              number_of_replicas: 0
            },
            mappings: mappings
          }
        )
        described_class.create_index(index_name, mappings)
      end
    end

    context 'when index already exists' do
      before do
        allow(described_class).to receive(:index_exists?).and_return(true)
      end

      it 'does not create the index' do
        expect(mock_indices_client).not_to receive(:create)
        described_class.create_index(index_name)
      end
    end
  end

  describe '.delete_index' do
    context 'when index exists' do
      before do
        allow(described_class).to receive(:index_exists?).and_return(true)
      end

      it 'deletes the index' do
        expect(mock_indices_client).to receive(:delete).with(index: index_name)
        described_class.delete_index(index_name)
      end
    end

    context 'when index does not exist' do
      before do
        allow(described_class).to receive(:index_exists?).and_return(false)
      end

      it 'does not attempt to delete the index' do
        expect(mock_indices_client).not_to receive(:delete)
        described_class.delete_index(index_name)
      end
    end
  end

  describe '.index_document' do
    it 'indexes a document' do
      expect(mock_client).to receive(:index).with(
        index: index_name,
        id: document_id,
        body: document
      )
      described_class.index_document(index_name, document_id, document)
    end
  end

  describe '.bulk_index' do
    let(:documents) {[
      { id: 1, title: 'Doc 1' },
      { id: 2, title: 'Doc 2' }
    ]}

    it 'performs a bulk index operation' do
      expected_operations = [
        { index: { _index: index_name, _id: 1 } },
        { id: 1, title: 'Doc 1' },
        { index: { _index: index_name, _id: 2 } },
        { id: 2, title: 'Doc 2' }
      ]

      expect(mock_client).to receive(:bulk).with(body: expected_operations)
      described_class.bulk_index(index_name, documents)
    end
  end

  describe '.search' do
    let(:query) { { query: { match_all: {} } } }

    it 'performs a search with the given query' do
      expect(mock_client).to receive(:search).with(
        index: index_name,
        body: query
      )
      described_class.search(index_name, query)
    end
  end

  describe '.get_document' do
    context 'when document exists' do
      it 'retrieves the document' do
        expect(mock_client).to receive(:get).with(
          index: index_name,
          id: document_id
        )
        described_class.get_document(index_name, document_id)
      end
    end

    context 'when document does not exist' do
      it 'returns nil' do
        allow(mock_client).to receive(:get)
          .and_raise(Elasticsearch::Transport::Transport::Errors::NotFound)

        expect(described_class.get_document(index_name, document_id)).to be_nil
      end
    end
  end

  describe '.update_document' do
    let(:update_fields) { { title: 'Updated Title' } }

    it 'updates the document with the provided fields' do
      expect(mock_client).to receive(:update).with(
        index: index_name,
        id: document_id,
        body: { doc: update_fields }
      )
      described_class.update_document(index_name, document_id, update_fields)
    end
  end

  describe '.delete_document' do
    context 'when document exists' do
      it 'deletes the document' do
        expect(mock_client).to receive(:delete).with(
          index: index_name,
          id: document_id
        )
        described_class.delete_document(index_name, document_id)
      end
    end

    context 'when document does not exist' do
      it 'returns nil without raising an error' do
        allow(mock_client).to receive(:delete)
          .and_raise(Elasticsearch::Transport::Transport::Errors::NotFound)

        expect(described_class.delete_document(index_name, document_id)).to be_nil
      end
    end
  end

  describe '.load_config' do
    context 'when config file exists' do
      let(:config_hash) { { 'development' => { 'host' => 'es-host', 'port' => 9200 } } }

      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:read).and_return("development:\n  host: es-host\n  port: 9200")
        allow(YAML).to receive(:load).and_return(config_hash)
        allow(Rails).to receive_message_chain(:env).and_return('development')
        allow(Rails).to receive_message_chain(:root, :join).and_return('path/to/config/elasticsearch.yml')
      end

      it 'loads the configuration from the file' do
        result = described_class.send(:load_config)
        expect(result['host']).to eq('es-host')
        expect(result['port']).to eq(9200)
      end
    end

    context 'when config file does not exist' do
      before do
        allow(File).to receive(:exist?).and_return(false)
        allow(Rails).to receive_message_chain(:root, :join).and_return('path/to/config/elasticsearch.yml')
      end

      it 'returns default configuration' do
        result = described_class.send(:load_config)
        expect(result['host']).to eq('localhost')
        expect(result['port']).to eq(9200)
      end
    end
  end
end
