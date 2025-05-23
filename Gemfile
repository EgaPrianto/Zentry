source "https://rubygems.org"

gem "i18n", "1.8.11"

gem 'faker', groups: [:development, :test]

gem 'dotenv-rails', groups: [:development, :test]

gem 'capybara', groups: [:development, :test]

gem 'selenium-webdriver', groups: [:development, :test]

# Add these gems to fix compatibility issues
gem "sorted_set", "~> 1.0"
gem "concurrent-ruby"
gem "tzinfo", "~> 2.0.6"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
# gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

# Elasticsearch gems with compatible versions
gem "elasticsearch", "~> 7.13.3"  # Use 7.x version to match elasticsearch-model
gem "elasticsearch-model", "~> 7.2.0"
gem "elasticsearch-rails", "~> 7.2.0"

# Kafka integration
gem "ruby-kafka", "~> 1.5.0"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  # gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false
  # Add to your Gemfile
  gem 'rails-controller-testing'
  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # RSpec for testing
  gem 'rspec-rails', '~> 6.0'
  gem 'factory_bot_rails'
  gem 'shoulda-matchers'
  gem 'database_cleaner-active_record'
  gem 'pry-rails'
  gem 'pry-byebug'
  gem 'simplecov', require: false # Add SimpleCov for test coverage reporting
end

gem "factory_bot", "~> 6.5"
