class SleepEntriesController < ApplicationController
  before_action :set_sleep_entry, only: %i[ show update destroy ]
  before_action :authenticate_user

  # GET /sleep_entries
  # Not to be confused with feed controller, this controller is responsible for fetching the sleep entries of the current user.
  def index
    limit = [(params[:limit] || 10).to_i, 10000].min
    offset = [(params[:offset] || 0).to_i, 10000].min

    query = SleepEntry.where(user_id: @current_user_id)
    @sleep_entries = query.limit(limit).offset(offset)
    total_count = query.count

    meta = {
      total_count: total_count,
      limit: limit,
      offset: offset,
      page: (offset / limit) + 1,
      total_pages: (total_count.to_f / limit).ceil
    }

    render json: {
      data: @sleep_entries,
      meta: meta
    }
  end

  # GET /sleep_entries/feed
  # Get all following users' sleep records from the previous week
  # sorted by sleep duration
  def feed
    limit = [(params[:limit] || 10).to_i, 10000].min
    offset = [(params[:offset] || 0).to_i, 10000].min

    options = {
      size: limit,
      from: offset,
      last_week: true # Filter to only show last week's entries
    }

    # This will use Elasticsearch to efficiently query and sort data
    results = SleepEntry.feed_for_user(@current_user_id, options)

    entries = []
    total_count = results['hits']['total']['value'] rescue 0

    if results['hits'] && results['hits']['hits'].present?
      entries = results['hits']['hits'].map do |hit|
        source = hit['_source']
        {
          id: source['sleep_entry_id'],
          user_id: source['author_id'],
          sleep_duration: source['sleep_duration'],
          created_at: source['created_at'],
          updated_at: source['updated_at']
        }
      end
    end

    meta = {
      total_count: total_count,
      limit: limit,
      offset: offset,
      page: (offset / limit) + 1,
      total_pages: (total_count.to_f / limit).ceil
    }

    render json: {
      data: entries,
      meta: meta
    }
  end

  # GET /sleep_entries/1
  def show
    render json: @sleep_entry
  end

  # POST /sleep_entries
  def create
    result = SleepEntryService.create_sleep_entry(@current_user_id, sleep_entry_params)

    if result[:success]
      render json: result[:sleep_entry], status: :created, location: result[:sleep_entry]
    else
      render json: result[:errors], status: :unprocessable_entity
    end
  end

  # PATCH/PUT /sleep_entries/1
  def update
    if @sleep_entry.update(sleep_entry_params)
      # Publish update event to Kafka
      render json: @sleep_entry
    else
      render json: @sleep_entry.errors, status: :unprocessable_entity
    end
  end

  # DELETE /sleep_entries/1
  def destroy
    # Capture ID before destruction
    sleep_entry_id = @sleep_entry.id
    user_id = @sleep_entry.user_id

    @sleep_entry.destroy!

    # Publish delete event to Kafka

    head :no_content
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_sleep_entry
      @sleep_entry = SleepEntry.find(params.fetch(:id))
    end

    # Only allow a list of trusted parameters through.
    def sleep_entry_params
      params.require(:sleep_entry).permit(:sleep_duration, :start_at, :user_id).merge(user_id: @current_user_id)
    end

    # Authenticate user as the login is not implemented in this code base this is a placeholder method.
    # In a real application, you would implement a proper authentication mechanism.
    def authenticate_user
      @current_user_id = request.headers['X-User-ID']

      unless @current_user_id.present?
        render json: { error: I18n.t('errors.sleep_entries.unauthorized') }, status: :unauthorized
        return false
      end
    end
end
