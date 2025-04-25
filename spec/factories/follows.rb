FactoryBot.define do
  factory :follow do
    association :user
    association :follower_user, factory: :user
  end
end
