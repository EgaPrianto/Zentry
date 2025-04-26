module Kafka
  class Producer
    class << self
      def publish(topic, payload, key = nil, partition_key = nil)
        with_producer do |producer|
          # Get the configured topic name or use the provided one
          topic_name = KAFKA_CONFIG.dig(:topics, topic.to_sym) || topic

          # Publish the message to Kafka
          Rails.logger.info("[KafkaProducer] Publishing message to topic: #{topic_name}")

          producer.produce(
            payload.to_json,
            topic: topic_name,
            key: key,
            partition_key: partition_key
          )

          # Deliver the messages to the Kafka broker
          producer.deliver_messages
          Rails.logger.info("[KafkaProducer] Successfully published message to topic: #{topic_name}")
          true
        end
      rescue => e
        Rails.logger.error("[KafkaProducer] Failed to publish message to #{topic}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        false
      end

      private

      def with_producer
        # Configure and create a new Kafka producer
        kafka = Kafka.new(
          seed_brokers: KAFKA_CONFIG[:brokers],
          client_id: KAFKA_CONFIG[:client_id]
        )

        # Configure the producer with settings from the config
        producer = kafka.producer(
          ack_timeout: KAFKA_CONFIG.dig(:producer, :ack_timeout),
          required_acks: KAFKA_CONFIG.dig(:producer, :required_acks),
          max_buffer_size: KAFKA_CONFIG.dig(:producer, :max_buffer_size),
          max_buffer_bytesize: KAFKA_CONFIG.dig(:producer, :max_buffer_bytesize),
          compression_codec: KAFKA_CONFIG.dig(:producer, :compression_codec)&.to_sym,
          compression_threshold: KAFKA_CONFIG.dig(:producer, :compression_threshold),
        )

        begin
          yield producer
        ensure
          # Always make sure to close the producer to avoid leaking resources
          producer.shutdown
        end
      end
    end
  end
end
