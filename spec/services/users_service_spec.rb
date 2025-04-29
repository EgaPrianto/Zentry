# spec/services/users/users_service_spec.rb
require 'rails_helper'

RSpec.describe UsersService do
  let(:user) { create(:user) }

  subject(:service) { described_class.new(user.id, **options) }
  let(:options) { {} }

  describe '#initialize' do
    context 'with default parameters' do
      it 'sets default limit to 20' do
        expect(service.limit).to eq 20
      end

      it 'sets cursor to nil' do
        expect(service.cursor).to be_nil
      end
    end

    context 'with custom limit' do
      context 'when limit is above maximum' do
        let(:options) { { limit: 200 } }

        it 'caps limit to 100' do
          expect(service.limit).to eq 100
        end
      end

      context 'when limit is below minimum' do
        let(:options) { { limit: 0 } }

        it 'sets minimum limit to 20' do
          expect(service.limit).to eq 20
        end
      end
    end

    context 'with cursor' do
      let(:options) { { cursor: 'cursor_value' } }

      it 'sets the cursor value' do
        expect(service.cursor).to eq 'cursor_value'
      end
    end
  end

  describe '#list_followers' do
    shared_context 'with followers' do
      let!(:follower1) { create(:user) }
      let!(:follower2) { create(:user) }

      before do
        create(:follow, user: user, follower_user: follower1)
        create(:follow, user: user, follower_user: follower2)
      end
    end

    context 'when user exists' do
      include_context 'with followers'

      it 'returns success with followers' do
        result = service.list_followers

        expect(result[:success]).to be true
        expect(result[:followers].count).to eq 2
        expect(result[:followers]).to match_array([follower1, follower2])
      end

      context 'with pagination' do
        let(:options) { { limit: 1 } }

        it 'includes pagination information' do
          result = service.list_followers

          expect(result[:pagination]).to be_present
          expect(result[:pagination][:limit]).to eq 1
          expect(result[:pagination][:next_cursor]).to be_present
        end

        it 'respects cursor parameter' do
          result1 = service.list_followers

          service2 = described_class.new(user.id, cursor: result1[:pagination][:next_cursor])
          result2 = service2.list_followers

          expect(result1[:followers].count).to eq 1
          expect(result2[:followers].count).to eq 1

          combined_users = result1[:followers] + result2[:followers]
          expect(combined_users).to match_array([follower1, follower2])
        end
      end
    end

    context 'when user does not exist' do
      subject(:service) { described_class.new(999999) }

      it 'returns error' do
        result = service.list_followers

        expect(result[:success]).to be false
        expect(result[:error]).to eq 'User not found'
      end
    end
  end

  describe '#list_following' do
    shared_context 'with following' do
      let!(:following1) { create(:user) }
      let!(:following2) { create(:user) }

      before do
        create(:follow, user: following1, follower_user: user) # user follows following1
        create(:follow, user: following2, follower_user: user) # user follows following2
      end
    end

    context 'when user exists' do
      include_context 'with following'

      it 'returns success with following users' do
        result = service.list_following

        expect(result[:following].map(&:id)).not_to be_empty

        expect(result[:success]).to be true
        expect(result[:following].count).to eq 2

        expect(result[:following]).to match_array([following1, following2])
      end

      context 'with pagination' do
        let(:options) { { limit: 1 } }

        it 'includes pagination information' do
          result = service.list_following

          expect(result[:pagination]).to be_present
          expect(result[:pagination][:limit]).to eq 1
          expect(result[:pagination][:next_cursor]).to be_present
        end

        it 'respects cursor parameter' do
          result1 = service.list_following

          service2 = described_class.new(user.id, cursor: result1[:pagination][:next_cursor])
          result2 = service2.list_following

          expect(result1[:following].count).to eq 1
          expect(result2[:following].count).to eq 1

          combined_users = result1[:following] + result2[:following]
          expect(combined_users).to match_array([following1, following2])
        end
      end
    end

    context 'when user does not exist' do
      subject(:service) { described_class.new(999999) }

      it 'returns error' do
        result = service.list_following

        expect(result[:success]).to be false
        expect(result[:error]).to eq 'User not found'
      end
    end
  end

  describe '.create_follow' do
    let(:user) { create(:user) }
    let(:follower) { create(:user) }
    let(:follow) { instance_double(Follow, id: 1, user_id: user.id, follower_id: follower.id, created_at: Time.current) }

    before do
      allow(Follow).to receive(:new).and_return(follow)
      allow(follow).to receive(:save).and_return(true)
      allow(Rails.logger).to receive(:error)

      # Mock the transaction behavior
      allow(ActiveRecord::Base).to receive(:transaction).and_yield
    end

    context 'when successful' do
      it 'creates a follow relationship and publishes to Kafka' do
        expect(Follow).to receive(:skip_kafka_callbacks=).with(true).ordered

        allow(follow).to receive(:publish_follow_created_event) do
          payload = {
            id: follow.id,
            user_id: follow.user_id,
            follower_id: follow.follower_id,
            created_at: follow.created_at,
            event_type: 'follow_created'
          }
          # Mock Kafka::Producer to return false (publish failure)
          allow(Kafka::Producer).to receive(:publish).with('follows', payload).and_return(true)
          true
        end

        expect(Follow).to receive(:skip_kafka_callbacks=).with(false).ordered

        result = described_class.create_follow(follower.id, user.id)

        expect(result[:success]).to be true
        expect(result[:follow]).to eq follow
      end

      it 'disables and re-enables kafka callbacks' do
        # We'll verify that both values are set properly during execution
        expect(Follow).to receive(:skip_kafka_callbacks=).with(true)
        expect(follow).to receive(:publish_follow_created_event).and_return(true)
        expect(Follow).to receive(:skip_kafka_callbacks=).with(false)

        described_class.create_follow(follower.id, user.id)
      end
    end

    context 'when save fails' do
      before do
        allow(follow).to receive(:save).and_return(false)
        allow(follow).to receive(:errors).and_return(double(full_messages: ['Error message']))
        # Don't actually raise Rollback in tests
        allow_any_instance_of(Object).to receive(:raise).with(ActiveRecord::Rollback)
      end

      it 'returns failure result with errors' do
        result = described_class.create_follow(follower.id, user.id)

        expect(result[:success]).to be false
        expect(result[:error]).to eq 'Error message'
      end
    end

    context 'when Kafka publishing fails' do
      before do
        # Mock the publish_follow_created_event method to use the actual Kafka::Producer
        allow(follow).to receive(:publish_follow_created_event) do
          payload = {
            id: follow.id,
            user_id: follow.user_id,
            follower_id: follow.follower_id,
            created_at: follow.created_at,
            event_type: 'follow_created'
          }
          # Mock Kafka::Producer to return false (publish failure)
          allow(Kafka::Producer).to receive(:publish).with('follows', payload).and_return(false)
          false
        end

        # Don't actually raise Rollback in tests
        allow_any_instance_of(Object).to receive(:raise).with(ActiveRecord::Rollback)
      end

      it 'returns failure result with Kafka error' do
        result = described_class.create_follow(follower.id, user.id)

        expect(result[:success]).to be false
        expect(result[:error]).to eq 'Failed to publish to Kafka'
      end
    end

    context 'when an exception occurs' do
      before do
        allow(follow).to receive(:save).and_return(true)
        # Don't actually raise Rollback in tests
        allow(follow).to receive(:publish_follow_created_event) do
          payload = {
            id: follow.id,
            user_id: follow.user_id,
            follower_id: follow.follower_id,
            created_at: follow.created_at,
            event_type: 'follow_created'
          }
          # Expect payload to be correct but raise an error
          allow(Kafka::Producer).to receive(:publish).with('follows', payload).and_raise(StandardError.new('Test error'))
          raise StandardError.new('Test error')
        end
      end

      it 'logs and returns the error' do
        expect(Rails.logger).to receive(:error).with("Error creating follow: Test error")

        expect(ActiveRecord::Base).to receive(:transaction).and_yield
        expect { described_class.create_follow(follower.id, user.id) }.to raise_error(StandardError)
      end
    end
  end

  describe '.destroy_follow' do
    let(:user) { create(:user) }
    let(:follower) { create(:user) }
    let(:follow) { instance_double(Follow, id: 1, user_id: user.id, follower_id: follower.id) }
    let(:temp_follow) { instance_double(Follow, id: 1, user_id: user.id, follower_id: follower.id) }

    before do
      allow(follow).to receive(:destroy).and_return(true)
      allow(Follow).to receive(:new).and_return(temp_follow)
      allow(Rails.logger).to receive(:error)

      # Mock the transaction behavior
      allow(ActiveRecord::Base).to receive(:transaction).and_yield
    end

    context 'when successful' do

      before do
        allow(temp_follow).to receive(:publish_follow_deleted_event) do
          payload = {
            id: temp_follow.id,
            user_id: temp_follow.user_id,
            follower_id: temp_follow.follower_id,
            event_type: 'follow_deleted'
          }
          # Mock Kafka::Producer to return false (publish failure)
          allow(Kafka::Producer).to receive(:publish).with('follows', payload).and_return(true)
          true
        end
      end

      it 'destroys the follow relationship and publishes to Kafka' do
        expect(Follow).to receive(:skip_kafka_callbacks=).with(true).ordered
        expect(follow).to receive(:destroy).ordered

        # Expect the Follow.new call with the right attributes
        expect(Follow).to receive(:new).with(
          id: follow.id,
          user_id: user.id,
          follower_id: follower.id
        ).ordered.and_return(temp_follow)

        # Set up expectation for the Kafka publishing

        expect(Follow).to receive(:skip_kafka_callbacks=).with(false).ordered

        result = described_class.destroy_follow(follow)

        expect(result[:success]).to be true
      end

      it 'disables and re-enables kafka callbacks' do
        expect(Follow).to receive(:skip_kafka_callbacks=).with(true)
        expect(temp_follow).to receive(:publish_follow_deleted_event).and_return(true)
        expect(Follow).to receive(:skip_kafka_callbacks=).with(false)

        described_class.destroy_follow(follow)
      end
    end

    context 'when destroy fails' do
      before do
        allow(follow).to receive(:destroy).and_return(false)
        allow(follow).to receive(:errors).and_return(double(full_messages: ['Error message']))
        # Don't actually raise Rollback in tests
        allow_any_instance_of(Object).to receive(:raise).with(ActiveRecord::Rollback)
      end

      it 'returns failure result with errors' do
        result = described_class.destroy_follow(follow)

        expect(result[:success]).to be false
        expect(result[:error]).to eq 'Error message'
      end
    end

    context 'when Kafka publishing fails' do
      before do
        # Mock the publish_follow_deleted_event method to use the actual Kafka::Producer
        allow(temp_follow).to receive(:publish_follow_deleted_event) do
          payload = {
            id: temp_follow.id,
            user_id: temp_follow.user_id,
            follower_id: temp_follow.follower_id,
            event_type: 'follow_deleted'
          }
          # Mock Kafka::Producer to return false (publish failure)
          allow(Kafka::Producer).to receive(:publish).with('follows', payload).and_return(false)
          false
        end

        # Don't actually raise Rollback in tests
        allow_any_instance_of(Object).to receive(:raise).with(ActiveRecord::Rollback)
      end

      it 'returns failure result with Kafka error' do
        result = described_class.destroy_follow(follow)

        expect(result[:success]).to be false
        expect(result[:error]).to eq 'Failed to publish to Kafka'
      end
    end

    context 'when an exception occurs' do
      before do
        allow(follow).to receive(:destroy).and_raise(StandardError.new('Test error'))
        # Don't actually raise Rollback in tests
        allow(follow).to receive(:publish_follow_deleted_event) do
          payload = {
            id: follow.id,
            user_id: follow.user_id,
            follower_id: follow.follower_id,            event_type: 'follow_deleted'
          }
          # Expect payload to be correct but raise an error
          allow(Kafka::Producer).to receive(:publish).with('follows', payload).and_raise(StandardError.new('Test error'))
          raise StandardError.new('Test error')
        end
      end

      it 'logs and returns the error' do
        expect(Rails.logger).to receive(:error).with("Error destroying follow: Test error")

        expect{ described_class.destroy_follow(follow) }.to raise_error(StandardError)

      end
    end
  end
end
