require 'elasticsearch'
require 'yaml'
require 'erb'
require 'active_support/core_ext/hash/indifferent_access'

module Elasticsearch
  class Connection
    class << self
      def client
        @client ||= create_client
      end

      def index_exists?(index_name)
        client.indices.exists?(index: index_name)
      end

      def create_index(index_name, mapping = {})
        unless index_exists?(index_name)
          client.indices.create(
            index: index_name,
            body: {
              settings: {
                number_of_shards: 1,
                number_of_replicas: 0
              },
              mappings: mapping
            }
          )
        end
      end

      def delete_index(index_name)
        client.indices.delete(index: index_name) if index_exists?(index_name)
      end

      def index_document(index_name, id, document)
        client.index(
          index: index_name,
          id: id,
          body: document
        )
      end

      def bulk_index(index_name, documents)
        operations = documents.flat_map do |doc|
          [
            { index: { _index: index_name, _id: doc[:id] } },
            doc
          ]
        end

        client.bulk(body: operations)
      end

      def search(index_name, query)
        client.search(
          index: index_name,
          body: query
        )
      end

      def get_document(index_name, id)
        client.get(
          index: index_name,
          id: id
        )
      rescue Elasticsearch::Transport::Transport::Errors::NotFound
        nil
      end

      def update_document(index_name, id, document)
        client.update(
          index: index_name,
          id: id,
          body: { doc: document }
        )
      end

      def delete_document(index_name, id)
        client.delete(
          index: index_name,
          id: id
        )
      rescue Elasticsearch::Transport::Transport::Errors::NotFound
        nil
      end

      private

      def create_client
        config = load_config

        client_options = {
          hosts: config['hosts'] || [config['host']],
          port: config['port'],
          log: config['log'] || false
        }

        client_options[:user] = config['user'] if config['user']
        client_options[:password] = config['password'] if config['password']

        ::Elasticsearch::Client.new(client_options)
      end

      def load_config
        config_file = ::Rails.root.join('config', 'elasticsearch.yml')
        if File.exist?(config_file)
          YAML.load(ERB.new(File.read(config_file)).result)[::Rails.env].with_indifferent_access
        else
          { 'host' => 'localhost', 'port' => 9200 }
        end
      end
    end
  end
end
