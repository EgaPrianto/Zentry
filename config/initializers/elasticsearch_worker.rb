Rails.application.config.after_initialize do
  if defined?(Rails::Server)
    # Start Sleep Entry Worker in a separate thread
    Thread.new do
      begin
        Rails.logger.info "Starting ElasticsearchSleepEntryWorker in background thread"
        ElasticsearchSleepEntryWorker.perform
      rescue => e
        Rails.logger.error "Error in ElasticsearchSleepEntryWorker: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    # Start Follow Worker in a separate thread
    Thread.new do
      begin
        Rails.logger.info "Starting ElasticsearchFollowWorker in background thread"
        ElasticsearchFollowWorker.perform
      rescue => e
        Rails.logger.error "Error in ElasticsearchFollowWorker: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end
end
