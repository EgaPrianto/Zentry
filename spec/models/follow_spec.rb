
require 'rails_helper'

RSpec.describe Follow do
  subject(:follow) { build(:follow, user: user, followed_user: followed_user) }
  let(:user) { create(:user) }
  let(:followed_user) { create(:user) }

  describe 'validations' do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_presence_of(:follower_id) }

    context 'when validating uniqueness' do
      before { create(:follow, user: user, followed_user: followed_user) }

      it 'enforces uniqueness of the follow relationship' do
        duplicate_follow = build(:follow, user: user, followed_user: followed_user)
        expect(duplicate_follow).not_to be_valid
        expect(duplicate_follow.errors[:user_id]).to include("has already been taken")
      end
    end
  end

  describe 'cursor pagination' do
    context 'when no cursor is provided' do
      it 'returns the most recent records up to the limit' do
        # Clear existing
        Follow.delete_all

        # Create test data
        follows = 5.times.map do |i|
          create(:follow,
                user: user,
                followed_user: create(:user, username: "test#{i}"),
                created_at: i.hours.ago)
        end

        # Act
        results = described_class.with_cursor_pagination(nil, 3)

        # Assert
        expect(results.count).to eq 3
        expect(results.to_a).to eq follows.first(3)
      end
    end

    context 'when a cursor is provided' do
      it 'returns records older than the cursor' do
        # Clear existing
        Follow.delete_all

        # Create test data
        follows = 3.times.map do |i|
          create(:follow,
                user: user,
                followed_user: create(:user, username: "test#{i}"),
                created_at: (5 - i).hours.ago)
        end

        # Create cursor
        cursor = described_class.encode_cursor(created_at: follows[1].created_at, id: follows[1].id)

        # Act
        results = described_class.with_cursor_pagination(cursor, 2)

        # Assert
        expect(results.count).to eq 1
        expect(results.first).to eq follows[2]
      end
    end
  end

  describe '.calculate_next_cursor' do

    context 'with empty results' do
      it { expect(described_class.calculate_next_cursor([], 10)).to be_nil }
    end

    context 'with results less than the limit' do
      it 'returns nil' do
        follows = 2.times.map { create(:follow, user: user, followed_user: create(:user)) }
        expect(described_class.calculate_next_cursor(follows, 3)).to be_nil
      end
    end

    context 'with results equal to the limit' do
      it 'returns a cursor based on the last record' do
        follows = 3.times.map { create(:follow, user: user, followed_user: create(:user)) }

        cursor = described_class.calculate_next_cursor(follows, 3)

        expect(cursor).not_to be_nil
        decoded = JSON.parse(Base64.strict_decode64(cursor)).symbolize_keys
        expect(decoded[:created_at]).to eq follows.last.created_at.as_json
        expect(decoded[:id]).to eq follows.last.id
      end
    end
  end

  describe 'cursor encoding and decoding' do
    it 'correctly encodes and decodes cursor data' do
      time = Time.current
      data = { created_at: time, id: 123 }

      # Act
      encoded = described_class.send(:encode_cursor, data)
      decoded = described_class.send(:decode_cursor, encoded)

      # Assert
      expect(decoded[:id]).to eq data[:id]
      expect(decoded[:created_at]).to eq data[:created_at].as_json
    end

    it 'returns empty hash for invalid cursor' do
      expect(described_class.send(:decode_cursor, "invalid-cursor")).to eq({})
    end
  end
end
