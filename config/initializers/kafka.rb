# Load Kafka configuration on app startup
require 'ruby-kafka'
require 'yaml'
require Rails.root.join('lib', 'kafka', 'consumer')
require Rails.root.join('lib', 'kafka', 'producer')

# Debug output to verify the Kafka class is available
Rails.logger.info("Kafka gem loaded: #{::Kafka.name rescue 'Not loaded properly'}")

# Load the Kafka configuration from config/kafka.yml
kafka_config_file = Rails.root.join('config', 'kafka.yml')
if File.exist?(kafka_config_file)
  # Use Psych.load with explicit aliases: true option
  yaml_content = ERB.new(File.read(kafka_config_file)).result
  kafka_config = YAML.safe_load(yaml_content, aliases: true, permitted_classes: [Symbol], symbolize_names: true)[Rails.env.to_sym]

  # Make configuration available globally - no need to symbolize keys as we're already doing it in safe_load
  KAFKA_CONFIG = kafka_config || {}

  # Debug output for Kafka configuration
  Rails.logger.info("Kafka configuration loaded successfully: brokers=#{KAFKA_CONFIG[:brokers].inspect}")
else
  Rails.logger.warn("Kafka configuration not found at #{kafka_config_file}")
  KAFKA_CONFIG = {}
end
