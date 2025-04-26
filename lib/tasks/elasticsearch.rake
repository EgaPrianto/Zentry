namespace :elasticsearch do
  desc "Set up Elasticsearch indices"
  task setup: :environment do
    puts "Setting up Elasticsearch indices..."
    Elasticsearch::IndexSetup.setup_indices
    puts "Elasticsearch indices created successfully!"
  end

  desc "Delete all Elasticsearch indices"
  task delete_indices: :environment do
    puts "Deleting Elasticsearch indices..."

    %w[sleep_entries feeds].each do |index_name|
      if Elasticsearch::Connection.index_exists?(index_name)
        Elasticsearch::Connection.delete_index(index_name)
        puts "Deleted index: #{index_name}"
      else
        puts "Index doesn't exist: #{index_name}"
      end
    end

    puts "Elasticsearch indices deleted successfully!"
  end

  desc "Reindex all data from database to Elasticsearch"
  task reindex: :environment do
    puts "Reindexing data from database to Elasticsearch..."

    # First ensure indices exist
    Elasticsearch::IndexSetup.setup_indices

    # Reindex sleep entries
    puts "Reindexing sleep entries..."
    total = SleepEntry.count
    processed = 0

    SleepEntry.find_in_batches(batch_size: 500) do |batch|
      batch.each do |sleep_entry|
        begin
          sleep_entry.index_in_elasticsearch
          processed += 1
          print "\rProcessed #{processed}/#{total} sleep entries"
        rescue => e
          puts "\nError indexing sleep entry #{sleep_entry.id}: #{e.message}"
        end
      end
    end

    puts "\nFinished reindexing data to Elasticsearch!"
  end
end
