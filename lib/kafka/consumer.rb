module Kafka
  class Consumer
    class << self
      # Method to subscribe and consume messages from a topic
      def consume(topic, consumer_group: nil, &block)
        # Get the configured topic name or use the provided one
        topic_name = KAFKA_CONFIG.dig(:topics, topic.to_sym) || topic
        group_id = consumer_group || KAFKA_CONFIG.dig(:consumer, :group_id)

        puts ("[KafkaConsumer] Starting consumer for topic: #{topic_name}, group: #{group_id}")

        with_consumer(group_id) do |consumer|
          # Subscribe to the topic
          consumer.subscribe(topic_name)

          # Process messages
          consumer.each_message do |message|
            begin
              puts ("[KafkaConsumer] Received message from topic: #{message.topic}, partition: #{message.partition}, offset: #{message.offset}")

              # Parse the JSON payload
              payload = JSON.parse(message.value)

              # Pass the parsed payload to the provided block
              block.call(payload, message.key, message)

              puts ("[KafkaConsumer] Successfully processed message from topic: #{message.topic}")
            rescue JSON::ParserError => e
              puts ("[KafkaConsumer] Failed to parse message as JSON from topic #{message.topic}: #{e.message}")
            rescue => e
              puts ("[KafkaConsumer] Error processing message from topic #{message.topic}: #{e.message}")
              puts (e.backtrace.join("\n"))
              # Re-raise the error to trigger the consumer's error handling
              raise
            end
          end
        end
      rescue => e
        binding.pry
        puts ("[KafkaConsumer] Error in consumer for topic #{topic}: #{e.message}")
        puts (e.backtrace.join("\n"))
        # Sleep before attempting to reconnect
        sleep 5
        retry
      end

      private

      def with_consumer(group_id)
        # Configure and create a new Kafka client
        kafka = Kafka.new(
          seed_brokers: KAFKA_CONFIG[:brokers],
          client_id: KAFKA_CONFIG[:client_id],
        )

        # Create a consumer with the configured settings
        consumer = kafka.consumer(
          group_id: group_id,
          session_timeout: KAFKA_CONFIG.dig(:consumer, :session_timeout),
          offset_retention_time: KAFKA_CONFIG.dig(:consumer, :offset_retention_time),
          heartbeat_interval: KAFKA_CONFIG.dig(:consumer, :heartbeat_interval)
        )

        begin
          yield consumer
        ensure
          # Always make sure to close the consumer to avoid leaking resources
          consumer.stop
        end
      end
    end
  end
end
