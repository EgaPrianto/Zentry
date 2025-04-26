namespace :kafka do
  desc "Start the sleep entry consumer worker"
  task consume_sleep_entries: :environment do
    puts "Starting sleep entry consumer worker..."
    SleepEntryConsumerWorker.perform
  end
end
