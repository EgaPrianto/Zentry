require 'elasticsearch'
require 'yaml'
require 'erb'

# Load Elasticsearch configuration
config_file = Rails.root.join('config', 'elasticsearch.yml')
if File.exist?(config_file)
  config = YAML.load(ERB.new(File.read(config_file)).result)[Rails.env]

  # Configure Elasticsearch client
  Elasticsearch::Model.client = Elasticsearch::Client.new(
    config.symbolize_keys.merge(
      retry_on_failure: 5,
      transport_options: { request: { timeout: 30 } }
    )
  )

  Rails.logger.info "Elasticsearch client initialized"
else
  Rails.logger.error "Elasticsearch configuration file not found"
end
