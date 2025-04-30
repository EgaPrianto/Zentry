require 'rails_helper'

RSpec.describe Kafka::Producer do
  let(:topic) { 'test_topic' }
  let(:payload) { { id: 123, message: 'test message' } }
  let(:key) { 'test_key' }
  let(:partition_key) { 'test_partition' }
  
  let(:mock_kafka) { double("Kafka::Client") }
  let(:mock_producer) { double("Kafka::Producer") }
  
  before do
    # Mock the Kafka client creation
    allow(Kafka).to receive(:new).and_return(mock_kafka)
    allow(mock_kafka).to receive(:producer).and_return(mock_producer)
    
    # Mock the logger
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    
    # Mock KAFKA_CONFIG
    stub_const('KAFKA_CONFIG', {
      brokers: ['kafka:9092'],
      client_id: 'zentry',
      producer: {
        ack_timeout: 5,
        required_acks: 1,
        max_buffer_size: 1000,
        max_buffer_bytesize: 10_000_000,
        compression_codec: 'snappy',
        compression_threshold: 1
      },
      topics: {
        test_topic: 'actual_test_topic'
      }
    })
  end

  describe '.publish' do
    context 'when successful' do
      before do
        allow(mock_producer).to receive(:produce)
        allow(mock_producer).to receive(:deliver_messages)
        allow(mock_producer).to receive(:shutdown)
      end

      it 'produces and delivers the message' do
        expect(mock_producer).to receive(:produce).with(
          payload.to_json,
          topic: 'actual_test_topic',
          key: key,
          partition_key: partition_key
        )
        expect(mock_producer).to receive(:deliver_messages)

        result = described_class.publish(topic, payload, key, partition_key)
        expect(result).to be true
      end

      it 'uses the correct topic from configuration' do
        expect(mock_producer).to receive(:produce).with(
          payload.to_json,
          topic: 'actual_test_topic',
          key: nil,
          partition_key: nil
        )

        described_class.publish(topic, payload)
      end

      it 'logs successful publishing' do
        allow(mock_producer).to receive(:produce)
        allow(mock_producer).to receive(:deliver_messages)

        expect(Rails.logger).to receive(:info).with("[KafkaProducer] Publishing message to topic: actual_test_topic")
        expect(Rails.logger).to receive(:info).with("[KafkaProducer] Successfully published message to topic: actual_test_topic")

        described_class.publish(topic, payload)
      end
    end

    context 'when topic is not in configuration' do
      let(:unknown_topic) { 'unknown_topic' }

      before do
        allow(mock_producer).to receive(:produce)
        allow(mock_producer).to receive(:deliver_messages)
        allow(mock_producer).to receive(:shutdown)
      end

      it 'uses the provided topic name' do
        expect(mock_producer).to receive(:produce).with(
          payload.to_json,
          topic: unknown_topic,
          key: nil,
          partition_key: nil
        )

        described_class.publish(unknown_topic, payload)
      end
    end

    context 'when an error occurs' do
      before do
        allow(mock_producer).to receive(:produce).and_raise(StandardError.new('Kafka connection error'))
        allow(mock_producer).to receive(:shutdown)
      end

      it 'logs the error and returns false' do
        expect(Rails.logger).to receive(:error).with(/Failed to publish message to test_topic: Kafka connection error/)
        expect(Rails.logger).to receive(:error).with(instance_of(String)) # For the backtrace

        result = described_class.publish(topic, payload)
        expect(result).to be false
      end
    end
  end

  describe '.with_producer' do
    it 'creates a producer with the correct configuration' do
      expect(Kafka).to receive(:new).with(
        seed_brokers: KAFKA_CONFIG[:brokers],
        client_id: KAFKA_CONFIG[:client_id]
      )

      expect(mock_kafka).to receive(:producer).with(
        ack_timeout: KAFKA_CONFIG[:producer][:ack_timeout],
        required_acks: KAFKA_CONFIG[:producer][:required_acks],
        max_buffer_size: KAFKA_CONFIG[:producer][:max_buffer_size],
        max_buffer_bytesize: KAFKA_CONFIG[:producer][:max_buffer_bytesize],
        compression_codec: KAFKA_CONFIG[:producer][:compression_codec].to_sym,
        compression_threshold: KAFKA_CONFIG[:producer][:compression_threshold]
      )

      expect(mock_producer).to receive(:shutdown)

      # Call the private method
      described_class.send(:with_producer) { |producer| producer }
    end

    it 'ensures producer is shut down even when an exception occurs' do
      expect(mock_producer).to receive(:shutdown)

      # Call the method with a block that raises an exception
      expect {
        described_class.send(:with_producer) { |producer| raise "Test error" }
      }.to raise_error("Test error")
    end
  end
end
