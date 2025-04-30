require 'rails_helper'

RSpec.describe Elasticsearch::FeedStrategy do
  describe '.use_fan_in?' do
    let(:user_id) { 123 }
    let(:follows) { instance_double(ActiveRecord::Relation) }

    context 'when user has fewer followers than threshold' do
      before do
        allow(Follow).to receive(:where).with(user_id: user_id).and_return(follows)
        allow(follows).to receive(:count).and_return(Elasticsearch::FeedStrategy::FOLLOWER_THRESHOLD - 1)
      end

      it 'returns false' do
        expect(described_class.use_fan_in?(user_id)).to be false
      end
    end

    context 'when user has exactly the threshold number of followers' do
      before do
        allow(Follow).to receive(:where).with(user_id: user_id).and_return(follows)
        allow(follows).to receive(:count).and_return(Elasticsearch::FeedStrategy::FOLLOWER_THRESHOLD)
      end

      it 'returns true' do
        expect(described_class.use_fan_in?(user_id)).to be true
      end
    end

    context 'when user has more followers than threshold' do
      before do
        allow(Follow).to receive(:where).with(user_id: user_id).and_return(follows)
        allow(follows).to receive(:count).and_return(Elasticsearch::FeedStrategy::FOLLOWER_THRESHOLD + 1)
      end

      it 'returns true' do
        expect(described_class.use_fan_in?(user_id)).to be true
      end
    end
  end

  describe '.get_celebrity_following_ids' do
    let(:follower_id) { 456 }
    let(:follows) { instance_double(ActiveRecord::Relation) }
    let(:following_ids) { [101, 102, 103] }

    before do
      allow(Follow).to receive(:where).with(follower_id: follower_id).and_return(follows)
      allow(follows).to receive(:pluck).with(:user_id).and_return(following_ids)
    end

    context 'when none of the followed users are celebrities' do
      before do
        following_ids.each do |id|
          user_follows = instance_double(ActiveRecord::Relation)
          allow(Follow).to receive(:where).with(user_id: id).and_return(user_follows)
          allow(user_follows).to receive(:count).and_return(Elasticsearch::FeedStrategy::FOLLOWER_THRESHOLD - 1)
        end
      end

      it 'returns an empty array' do
        expect(described_class.get_celebrity_following_ids(follower_id)).to eq([])
      end
    end

    context 'when some of the followed users are celebrities' do
      before do
        # User 101 is not a celebrity
        user_101_follows = instance_double(ActiveRecord::Relation)
        allow(Follow).to receive(:where).with(user_id: 101).and_return(user_101_follows)
        allow(user_101_follows).to receive(:count).and_return(Elasticsearch::FeedStrategy::FOLLOWER_THRESHOLD - 1)

        # User 102 is a celebrity
        user_102_follows = instance_double(ActiveRecord::Relation)
        allow(Follow).to receive(:where).with(user_id: 102).and_return(user_102_follows)
        allow(user_102_follows).to receive(:count).and_return(Elasticsearch::FeedStrategy::FOLLOWER_THRESHOLD)

        # User 103 is a celebrity
        user_103_follows = instance_double(ActiveRecord::Relation)
        allow(Follow).to receive(:where).with(user_id: 103).and_return(user_103_follows)
        allow(user_103_follows).to receive(:count).and_return(Elasticsearch::FeedStrategy::FOLLOWER_THRESHOLD + 1)
      end

      it 'returns only the celebrity user IDs' do
        expect(described_class.get_celebrity_following_ids(follower_id)).to contain_exactly(102, 103)
      end
    end

    context 'when all of the followed users are celebrities' do
      before do
        following_ids.each do |id|
          user_follows = instance_double(ActiveRecord::Relation)
          allow(Follow).to receive(:where).with(user_id: id).and_return(user_follows)
          allow(user_follows).to receive(:count).and_return(Elasticsearch::FeedStrategy::FOLLOWER_THRESHOLD + id) # All above threshold
        end
      end

      it 'returns all followed user IDs' do
        expect(described_class.get_celebrity_following_ids(follower_id)).to contain_exactly(101, 102, 103)
      end
    end
  end

  describe '.get_regular_following_ids' do
    let(:follower_id) { 456 }
    let(:following_ids) { [101, 102, 103, 104] }
    let(:celebrity_ids) { [102, 104] }

    before do
      allow(described_class).to receive(:get_celebrity_following_ids)
        .with(follower_id).and_return(celebrity_ids)

      # Mock the basic follow query since get_regular_following_ids will call it
      follows = instance_double(ActiveRecord::Relation)
      allow(Follow).to receive(:where).with(follower_id: follower_id).and_return(follows)
      allow(follows).to receive(:pluck).with(:user_id).and_return(following_ids)
    end

    it 'returns only the non-celebrity user IDs' do
      expect(described_class.get_regular_following_ids(follower_id)).to contain_exactly(101, 103)
    end

    context 'when there are no celebrity follows' do
      before do
        allow(described_class).to receive(:get_celebrity_following_ids)
          .with(follower_id).and_return([])
      end

      it 'returns all followed user IDs' do
        expect(described_class.get_regular_following_ids(follower_id)).to contain_exactly(101, 102, 103, 104)
      end
    end

    context 'when all followed users are celebrities' do
      before do
        allow(described_class).to receive(:get_celebrity_following_ids)
          .with(follower_id).and_return(following_ids)
      end

      it 'returns an empty array' do
        expect(described_class.get_regular_following_ids(follower_id)).to eq([])
      end
    end
  end
end
