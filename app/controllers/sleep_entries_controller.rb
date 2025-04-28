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
  # sorted by sleep duration with special handling for celebrity users
  def feed
    limit = [(params[:limit] || 10).to_i, 10000].min
    offset = [(params[:offset] || 0).to_i, 10000].min

    options = {
      size: limit,
      from: offset,
      last_week: true # Filter to only show last week's entries
    }

    # Directly use Elasticsearch service which handles both fan-out (regular users)
    # and fan-in (celebrity users) approaches
    results = ::Elasticsearch::SleepEntryService.feed_for_user(@current_user_id, options)

    entries = []
    total_count = results['hits']['total']['value'] rescue 0

    if results['hits'] && results['hits']['hits'].present?
      entries = results['hits']['hits'].map do |hit|
        source = hit['_source']
        {
          id: source['sleep_entry_id'],
          user_id: source['user_id'],
          author_id: source['author_id'],
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
      render json: {
        sleep_entry: result[:sleep_entry],
        message: I18n.t('success.sleep_entries.created')
      }, status: :created, location: result[:sleep_entry]
    else
      render json: { error: result[:errors] }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /sleep_entries/1
  def update
    if @sleep_entry.update(sleep_entry_params)
      # Kafka publishing now happens in SleepEntry model's after_update callback
      render json: {
        sleep_entry: @sleep_entry,
        message: I18n.t('success.sleep_entries.updated')
      }, status: :ok
    else
      render json: { error: @sleep_entry.errors }, status: :unprocessable_entity
    end
  end

  # DELETE /sleep_entries/1
  def destroy
    @sleep_entry.destroy!
    # Kafka publishing now happens in SleepEntry model's after_destroy callback
    render json: { message: I18n.t('success.sleep_entries.deleted') }, status: :ok
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
