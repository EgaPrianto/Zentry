namespace :cequel do
  task :keyspace => :environment do
    Cequel::Schema::Keyspace.create(
      Rails.application.config_for(:cequel)[:keyspace],
      simple: true,
      replication_factor: 1
    )
  end
end
