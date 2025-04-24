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

  # GET /sleep_entries/1
  def show
    render json: @sleep_entry
  end

  # POST /sleep_entries
  def create
    # TODO: Refactor into a service class to handle:
    # 1. Sleep entry creation
    # 2. Feed event duplication to Cassandra
    # 3. Feed entry management in Cassandra
    @sleep_entry = SleepEntry.new(sleep_entry_params)

    if @sleep_entry.save
      render json: @sleep_entry, status: :created, location: @sleep_entry
    else
      render json: @sleep_entry.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /sleep_entries/1
  def update
    # TODO: Refactor into a service class to handle:
    # 1. Sleep entry update
    # 2. Feed event duplication to Cassandra
    # 3. Feed entry management in Cassandra
    if @sleep_entry.update(sleep_entry_params)
      render json: @sleep_entry
    else
      render json: @sleep_entry.errors, status: :unprocessable_entity
    end
  end

  # DELETE /sleep_entries/1
  def destroy
    @sleep_entry.destroy!
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_sleep_entry
      @sleep_entry = SleepEntry.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def sleep_entry_params
      params.fetch(:sleep_entry, {}).merge(user_id: @current_user_id)
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
