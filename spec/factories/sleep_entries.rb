FactoryBot.define do
  factory :sleep_entry do
    user
    start_at { Time.current - 8.hours }
    sleep_duration { 28800 } # 8 hours in seconds
  end
end
