namespace :kafka do
  desc "Start the sleep entry consumer worker"
  task consume_sleep_entries: :environment do
    puts "Starting sleep entry consumer worker..."
    ElasticsearchSleepEntryWorker.perform
  end
  desc "Start the feed consumer worker"
  task consume_feed: :environment do
    puts "Starting feed consumer worker..."
    ElasticsearchFollowWorker.perform
  end
end
