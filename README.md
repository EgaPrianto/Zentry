# Zentry

Zentry is a sleep tracking social application that allows users to record their sleep entries and follow other users to see their sleep patterns. The application is built on a distributed architecture using Ruby on Rails, PostgreSQL, Elasticsearch, and Kafka.

## Overview

Zentry helps users track their sleep duration and patterns while also providing social features to follow friends and view their sleep entries. The application uses an optimized hybrid fan-out/fan-in architecture to efficiently handle both regular users and celebrity users with large follower counts.

### Key Features

- **Sleep Entry Management**: Create, update, and delete sleep entries
- **Social Follow System**: Follow other users to see their sleep entries
- **Hybrid Feed Architecture**: 
  - Fan-out approach for regular users (write-time duplication)
  - Fan-in approach for celebrity users (read-time aggregation) 
- **Real-time Data Processing**: Event-driven architecture with Kafka

## Technical Stack

- **Framework**: Ruby on Rails 8.0 (API only)
- **Database**: PostgreSQL
- **Search & Indexing**: Elasticsearch 7.13.3
- **Event Streaming**: Kafka via ruby-kafka gem
- **Testing**: RSpec

## Architecture

### Data Flow

1. User actions (creating sleep entries, following users) generate events
2. Events are published to Kafka topics
3. Background workers consume these events and update Elasticsearch indices
4. API endpoints query Elasticsearch for efficient data retrieval

### Feed Implementation

The system uses a hybrid approach for social feeds:

- **Fan-out**: When a regular user posts a sleep entry, copies are stored in each follower's feed index
- **Fan-in**: For users with many followers (celebrities), entries are stored only once and aggregated at read-time
- **Combined**: For users who follow both regular and celebrity users, results are merged from both approaches

## Setup

### Prerequisites

- Ruby 3.x
- PostgreSQL
- Elasticsearch 7.x
- Kafka & Zookeeper
- Docker (optional for containerized setup)
- Bundler

### Installation

1. Clone the repository:
```bash
git clone https://github.com/EgaPrianto/Zentry.git
cd Zentry
```

2. Install dependencies:
```bash
bundle install
```

3. Copy the environment variables file and configure:
```bash
cp env.sample .env
# Edit .env with your configuration
```

4. Setup the database:
```bash
bin/rails db:setup
```

5. Setup Elasticsearch indices:
```bash
bin/rails elasticsearch:setup
```

### Running the Application

Start the Rails server:

```bash
bin/rails server
```

The Elasticsearch workers for processing Kafka events are automatically started when the Rails server runs, thanks to the initializer in `config/initializers/elasticsearch_worker.rb`.

### Running Kafka Workers (Separate Deployment)

For separate deployment scenarios where you want to run the Kafka workers independently from the Rails application (e.g., on different servers or containers), use these commands:

```bash
# Start the sleep entry consumer
bin/rails kafka:consume_sleep_entries

# Start the feed consumer 
bin/rails kafka:consume_feed
```

This separation allows for better resource allocation and scaling of the worker processes independently from the web application.

## Development

### Testing

Run the test suite with:

```bash
bin/rails spec
```

### Elasticsearch Commands

```bash
# Setup indices
bin/rails elasticsearch:setup

# Delete indices
bin/rails elasticsearch:delete_indices

# Reindex data
bin/rails elasticsearch:reindex
```

## API Endpoints

The application provides a RESTful API for:

- User management
- Sleep entry CRUD operations
- Follow/unfollow functionality
- Feed retrieval

For detailed API documentation, refer to the API docs (coming soon).

## Deployment

WIP

## License

-
