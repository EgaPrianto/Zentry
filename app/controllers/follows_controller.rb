class FollowsController < ApplicationController
  before_action :authenticate_user

  # GET /users/:user_id/followers
  def followers
    limit = params[:limit] || 20
    cursor = params[:cursor]

    result = UsersService.new(params[:user_id], limit: limit, cursor: cursor).list_followers

    if result[:success]
      render json: {
        followers: result[:followers],
        pagination: result[:pagination]
      }, status: :ok
    else
      render json: { error: result[:error] }, status: :not_found
    end
  end

  # GET /users/:user_id/following
  def following
    limit = params[:limit] || 20
    cursor = params[:cursor]

    result = UsersService.new(params[:user_id], limit: limit, cursor: cursor).list_following

    if result[:success]
      render json: {
        following: result[:following],
        pagination: result[:pagination]
      }, status: :ok
    else
      render json: { error: result[:error] }, status: :not_found
    end
  end

  # POST /users/:user_id/follow
  def create
    @follower_user = User.find(params[:user_id])

    if @current_user_id.to_s == params[:user_id].to_s
      render json: { error: I18n.t('errors.follows.cannot_follow_self') }, status: :unprocessable_entity
      return
    end

    @follow = Follow.find_by(user_id: @follower_user.id, follower_id: @current_user_id)

    if @follow
      render json: { error: I18n.t('errors.follows.already_following') }, status: :unprocessable_entity
      return
    end

    # Use the service instead of handling transactions directly
    result = UsersService.create_follow(@current_user_id, @follower_user.id)

    if result[:success]
      render json: {
        follow: result[:follow],
        message: I18n.t('success.follows.created', name: @follower_user.name)
      }, status: :created
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  # DELETE /users/:user_id/follow
  def destroy
    @follower_user = User.find(params[:user_id])
    @follow = Follow.find_by(user_id: @follower_user.id, follower_id: @current_user_id)

    if @follow
      # Use the service instead of handling transactions directly
      result = UsersService.destroy_follow(@follow)

      if result[:success]
        render json: {
          message: I18n.t('success.follows.deleted', name: @follower_user.name)
        }, status: :ok
      else
        render json: { error: result[:error] }, status: :unprocessable_entity
      end
    else
      render json: { error: I18n.t('errors.follows.not_following') }, status: :not_found
    end
  end

  private

  # Authenticate user from headers and set current_user_id
  def authenticate_user
    @current_user_id = request.headers['X-User-ID']

    unless @current_user_id.present?
      render json: { error: I18n.t('errors.follows.unauthorized') }, status: :unauthorized
      return false
    end
  end
end
