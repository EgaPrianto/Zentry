Rails.application.config.after_initialize do
  if defined?(Rails::Server)
    Thread.new do
      begin
        Rails.logger.info "Starting ElasticsearchIndexingWorker in background thread"
        ElasticsearchIndexingWorker.perform
      rescue => e
        Rails.logger.error "Error in ElasticsearchIndexingWorker: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end
end
