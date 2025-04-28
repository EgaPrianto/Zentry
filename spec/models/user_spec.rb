require 'rails_helper'

RSpec.describe User do
  subject(:user) { create(:user) }
  
  describe 'associations' do
    it { is_expected.to have_many(:sleep_entries).dependent(:destroy) }
    
    it { is_expected.to have_many(:follows).with_foreign_key(:follower_id).dependent(:destroy) }
    it { is_expected.to have_many(:following_users).through(:follows).source(:user) }
    
    it { is_expected.to have_many(:followers).class_name('Follow').with_foreign_key(:user_id).dependent(:destroy) }
    it { is_expected.to have_many(:follower_users).through(:followers).source(:follower_user) }
  end
  
  describe 'dependent destroy behavior' do
    context 'with sleep entries' do
      it 'destroys associated sleep entries when user is destroyed' do
        # Create a sleep entry for this user
        SleepEntry.skip_kafka_callbacks = true
        sleep_entry = create(:sleep_entry, user: user)
        
        expect { user.destroy }.to change { SleepEntry.count }.by(-1)
        expect { sleep_entry.reload }.to raise_error(ActiveRecord::RecordNotFound)
        SleepEntry.skip_kafka_callbacks = false
      end
    end
    
    context 'with follows' do
      it 'destroys follows where user is the follower' do
        Follow.skip_kafka_callbacks = true
        # User follows someone else
        follow = create(:follow, follower_user: user)
        
        expect { user.destroy }.to change { Follow.count }.by(-1)
        expect { follow.reload }.to raise_error(ActiveRecord::RecordNotFound)
        Follow.skip_kafka_callbacks = false
      end
      
      it 'destroys follows where user is being followed' do
        Follow.skip_kafka_callbacks = true
        # User is being followed by someone else
        follow = create(:follow, user: user)
        
        expect { user.destroy }.to change { Follow.count }.by(-1)
        expect { follow.reload }.to raise_error(ActiveRecord::RecordNotFound)
        Follow.skip_kafka_callbacks = false
      end
    end
  end
end