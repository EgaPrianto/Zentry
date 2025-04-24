class FollowsController < ApplicationController
  before_action :authenticate_user

  # POST /users/:user_id/follow
  def create
    @followed_user = User.find(params[:user_id])

    if @current_user_id.to_s == params[:user_id].to_s
      render json: { error: I18n.t('errors.follows.cannot_follow_self') }, status: :unprocessable_entity
      return
    end

    @follow = Follow.find_by(user_id: @current_user_id, follower_id: @followed_user.id)

    if @follow
      render json: { error: I18n.t('errors.follows.already_following') }, status: :unprocessable_entity
      return
    end

    @follow = Follow.new(user_id: @current_user_id, follower_id: @followed_user.id)

    if @follow.save
      render json: @follow, status: :created
    else
      render json: @follow.errors, status: :unprocessable_entity
    end
  end

  # DELETE /users/:user_id/follow
  def destroy
    @followed_user = User.find(params[:user_id])
    @follow = Follow.find_by(user_id: @current_user_id, follower_id: @followed_user.id)

    if @follow
      @follow.destroy
      head :no_content
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
