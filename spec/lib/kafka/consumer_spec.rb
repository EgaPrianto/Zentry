require 'rails_helper'

RSpec.describe Kafka::Consumer do
  let(:topic) { 'test_topic' }
  let(:consumer_group) { 'test_consumer_group' }
  let(:mock_kafka) { double("Kafka::Client") }
  let(:mock_consumer) { double("Kafka::Consumer") }
  let(:mock_message) {
    double(
      'Kafka::FetchedMessage',
      value: '{"id": 123, "data": "test"}',
      key: 'test_key',
      topic: 'actual_test_topic',
      partition: 0,
      offset: 42
    )
  }

  before do
    # Mock the Kafka client creation
    allow(Kafka).to receive(:new).and_return(mock_kafka)
    allow(mock_kafka).to receive(:consumer).and_return(mock_consumer)

    # Basic mock configuration for the consumer
    allow(mock_consumer).to receive(:subscribe)
    allow(mock_consumer).to receive(:stop)

    # Allow ALL puts messages since our implementation uses puts in many places
    allow(described_class).to receive(:puts).with(anything)

    # Mock KAFKA_CONFIG
    stub_const('KAFKA_CONFIG', {
      brokers: ['kafka:9092'],
      client_id: 'zentry',
      consumer: {
        group_id: 'zentry-consumer',
        session_timeout: 30,
        offset_retention_time: 7_200,
        heartbeat_interval: 10
      },
      topics: {
        test_topic: 'actual_test_topic'
      }
    })
  end

  describe '.consume' do
    let(:block_called) { false }
    let(:block_payload) { nil }

    # Mock the retry behavior to prevent infinite loop in tests
    before do
      # Make sure we don't retry forever in tests
      allow(described_class).to receive(:consume).and_call_original

      # For the retry test, allow one retry then exit
      retry_count = 0
      allow(described_class).to receive(:sleep) do |duration|
        retry_count += 1
        raise "Exiting test retry loop" if retry_count > 1
      end
    end

    it 'creates a consumer with the correct configuration' do
      expect(Kafka).to receive(:new).with(
        seed_brokers: KAFKA_CONFIG[:brokers],
        client_id: KAFKA_CONFIG[:client_id]
      )

      expect(mock_kafka).to receive(:consumer).with(
        group_id: consumer_group,
        session_timeout: KAFKA_CONFIG[:consumer][:session_timeout],
        offset_retention_time: KAFKA_CONFIG[:consumer][:offset_retention_time],
        heartbeat_interval: KAFKA_CONFIG[:consumer][:heartbeat_interval]
      )

      # Mock each_message to avoid infinite loop
      allow(mock_consumer).to receive(:each_message).and_return(nil)

      described_class.consume(topic, consumer_group: consumer_group) { |_| }
    end

    it 'subscribes to the correct topic' do
      expect(mock_consumer).to receive(:subscribe).with('actual_test_topic')

      # Mock each_message to avoid infinite loop
      allow(mock_consumer).to receive(:each_message).and_return(nil)

      described_class.consume(topic, consumer_group: consumer_group) { |_| }
    end

    it 'processes each message' do
      # Mock each_message to yield one message and then return
      expect(mock_consumer).to receive(:each_message).and_yield(mock_message).and_return(nil)

      # Check if the block is called with correct parsed payload
      described_class.consume(topic, consumer_group: consumer_group) do |payload, key, msg|
        expect(payload).to eq({ 'id' => 123, 'data' => 'test' })
        expect(key).to eq('test_key')
        expect(msg).to eq(mock_message)
      end
    end

    context 'when a JSON parse error occurs' do
      let(:invalid_json_message) {
        double(
          'Kafka::FetchedMessage',
          value: '{invalid_json',
          key: nil,
          topic: 'actual_test_topic',
          partition: 0,
          offset: 42
        )
      }

      it 'logs the error and continues' do
        # Mock each_message to yield an invalid JSON message and then return
        expect(mock_consumer).to receive(:each_message).and_yield(invalid_json_message).and_return(nil)

        # Expect a JSON parse error message - note we're matching a substring now
        expect(described_class).to receive(:puts).with(/Failed to parse message as JSON/)

        # The block should not be called because JSON parsing failed
        block_called = false
        described_class.consume(topic, consumer_group: consumer_group) do |_|
          block_called = true
        end

        expect(block_called).to be false
      end
    end

    context 'when an error occurs during message processing' do
      it 'logs the error message' do
        # Since we can't easily test the full error re-raising behavior due to the retry loop,
        # we'll test that the error is properly logged, which is a key part of the error handling

        # Mock each_message to yield one message
        allow(mock_consumer).to receive(:each_message).and_yield(mock_message)

        # This is the key expectation - we should see the error being logged
        expect(described_class).to receive(:puts).with(/Error processing message/).at_least(:once)

        # Stop after logging the error - don't let the test enter the retry loop
        allow(described_class).to receive(:sleep).and_raise("Test complete")

        # The block will raise an error
        expect {
          described_class.consume(topic, consumer_group: consumer_group) do |_|
            raise StandardError.new("Processing error")
          end
        }.to raise_error("Test complete")

        # If we get here, it means the error was logged properly before entering the retry loop
      end
    end

    context 'when no consumer group is provided' do
      it 'uses the default from configuration' do
        expect(mock_kafka).to receive(:consumer).with(
          group_id: KAFKA_CONFIG[:consumer][:group_id],
          session_timeout: KAFKA_CONFIG[:consumer][:session_timeout],
          offset_retention_time: KAFKA_CONFIG[:consumer][:offset_retention_time],
          heartbeat_interval: KAFKA_CONFIG[:consumer][:heartbeat_interval]
        )

        # Mock each_message to avoid infinite loop
        allow(mock_consumer).to receive(:each_message).and_return(nil)

        described_class.consume(topic) { |_| }
      end
    end

    context 'when a consumer error occurs' do
      it 'retries after sleeping' do
        # We're only going to allow 1 retry for the test
        allow(described_class).to receive(:sleep).with(5).once

        # First call raises error, second succeeds
        call_count = 0
        allow(Kafka).to receive(:new) do
          call_count += 1
          if call_count == 1
            raise RuntimeError.new("Connection error")
          else
            mock_kafka
          end
        end

        # Each message should return nil to exit the loop
        allow(mock_consumer).to receive(:each_message).and_return(nil)

        # Testing that it tries to connect twice - first fails, second succeeds
        expect(Kafka).to receive(:new).exactly(2).times

        # This should not hang
        described_class.consume(topic) { |_| }
      end
    end
  end

  describe '.with_consumer' do
    it 'ensures consumer is stopped even when an exception occurs' do
      expect(mock_consumer).to receive(:stop)

      # Call the method with a block that raises an exception
      expect {
        described_class.send(:with_consumer, consumer_group) { |consumer| raise "Test error" }
      }.to raise_error("Test error")
    end
  end
end
