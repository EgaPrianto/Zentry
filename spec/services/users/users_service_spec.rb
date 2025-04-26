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
end
