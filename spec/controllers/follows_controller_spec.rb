require 'rails_helper'

RSpec.describe FollowsController, type: :controller do
  let(:user_id) { '123' }
  let(:current_user_id) { '456' }
  let(:user) { instance_double(User, id: user_id, name: 'Test User') }
  let(:current_user) { instance_double(User, id: current_user_id, name: 'Current User') }
  let(:follow) { instance_double(Follow, id: 1, user_id: user_id, follower_id: current_user_id) }
  let(:users_service) { instance_double(UsersService) }

  before do
    request.headers['X-User-ID'] = current_user_id
  end

  describe 'GET #followers' do
    let(:limit) { '20' }
    let(:cursor) { 'some-cursor-value' }
    let(:followers_result) do
      {
        success: true,
        followers: [{ id: 789, name: 'Follower User' }],
        pagination: { next_cursor: 'next-cursor-value' }
      }
    end

    context 'when successful' do
      before do
        allow(UsersService).to receive(:new).with(user_id, limit: limit, cursor: cursor).and_return(users_service)
        allow(users_service).to receive(:list_followers).and_return(followers_result)

        get :followers, params: { user_id: user_id, limit: limit, cursor: cursor }
      end

      it 'returns http success' do
        expect(response).to have_http_status(:success)
      end

      it 'returns followers and pagination info' do
        body = JSON.parse(response.body)
        followers_result[:followers].each do |user|
          user.stringify_keys!
        end
        expect(body['followers']).to eq(followers_result[:followers])
        expect(body['pagination']).to eq(followers_result[:pagination].stringify_keys)
      end
    end

    context 'when user is not found' do
      let(:error_result) { { success: false, error: 'User not found' } }

      before do
        allow(UsersService).to receive(:new).with(user_id, limit: 20, cursor: nil).and_return(users_service)
        allow(users_service).to receive(:list_followers).and_return(error_result)

        get :followers, params: { user_id: user_id }
      end

      it 'returns http not found' do
        expect(response).to have_http_status(:not_found)
      end

      it 'returns error message' do
        body = JSON.parse(response.body)
        expect(body['error']).to eq(error_result[:error])
      end
    end
  end

  describe 'GET #following' do
    let(:limit) { '20' }
    let(:cursor) { 'some-cursor-value' }
    let(:following_result) do
      {
        success: true,
        following: [{ id: 789, name: 'Following User' }],
        pagination: { next_cursor: 'next-cursor-value' }
      }
    end

    context 'when successful' do
      before do
        allow(UsersService).to receive(:new).with(user_id, limit: limit, cursor: cursor).and_return(users_service)
        allow(users_service).to receive(:list_following).and_return(following_result)

        get :following, params: { user_id: user_id, limit: limit, cursor: cursor }
      end

      it 'returns http success' do
        expect(response).to have_http_status(:success)
      end

      it 'returns following and pagination info' do
        body = JSON.parse(response.body)
        following_result[:following].each do |user|
          user.stringify_keys!
        end
        expect(body['following']).to eq(following_result[:following])
        expect(body['pagination']).to eq(following_result[:pagination].stringify_keys)
      end
    end

    context 'when user is not found' do
      let(:error_result) { { success: false, error: 'User not found' } }

      before do
        allow(UsersService).to receive(:new).with(user_id, limit: 20, cursor: nil).and_return(users_service)
        allow(users_service).to receive(:list_following).and_return(error_result)

        get :following, params: { user_id: user_id }
      end

      it 'returns http not found' do
        expect(response).to have_http_status(:not_found)
      end

      it 'returns error message' do
        body = JSON.parse(response.body)
        expect(body['error']).to eq(error_result[:error])
      end
    end
  end

  describe 'POST #create' do
    context 'when successfully following a user' do
      let(:create_result) { { success: true, follow: follow } }

      before do
        allow(User).to receive(:find).with(user_id).and_return(user)
        allow(Follow).to receive(:find_by).with(user_id: user_id, follower_id: current_user_id).and_return(nil)
        allow(UsersService).to receive(:create_follow).with(current_user_id, user_id).and_return(create_result)
        allow(I18n).to receive(:t).with('success.follows.created', name: user.name).and_return('You are now following Test User')

        post :create, params: { user_id: user_id }
      end

      it 'returns http created status' do
        expect(response).to have_http_status(:created)
      end

      it 'returns follow data and success message' do
        body = JSON.parse(response.body)

        expect(body['follow']).to eq(JSON.parse(create_result[:follow].to_json))
        expect(body['message']).to eq('You are now following Test User')
      end
    end

    context 'when trying to follow yourself' do
      before do
        allow(I18n).to receive(:t).with('errors.follows.cannot_follow_self').and_return('You cannot follow yourself')
        allow(User).to receive(:find).with(current_user_id).and_return(current_user)

        post :create, params: { user_id: current_user_id }
      end

      it 'returns unprocessable entity status' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error message' do
        body = JSON.parse(response.body)
        expect(body['error']).to eq('You cannot follow yourself')
      end
    end

    context 'when already following the user' do
      before do
        allow(User).to receive(:find).with(user_id).and_return(user)
        allow(Follow).to receive(:find_by).with(user_id: user_id, follower_id: current_user_id).and_return(follow)
        allow(I18n).to receive(:t).with('errors.follows.already_following').and_return('You are already following this user')

        post :create, params: { user_id: user_id }
      end

      it 'returns unprocessable entity status' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error message' do
        body = JSON.parse(response.body)
        expect(body['error']).to eq('You are already following this user')
      end
    end

    context 'when follow creation fails' do
      let(:create_result) { { success: false, error: 'Failed to create follow' } }

      before do
        allow(User).to receive(:find).with(user_id).and_return(user)
        allow(Follow).to receive(:find_by).with(user_id: user_id, follower_id: current_user_id).and_return(nil)
        allow(UsersService).to receive(:create_follow).with(current_user_id, user_id).and_return(create_result)

        post :create, params: { user_id: user_id }
      end

      it 'returns unprocessable entity status' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error message' do
        body = JSON.parse(response.body)
        expect(body['error']).to eq(create_result[:error])
      end
    end
  end

  describe 'DELETE #destroy' do
    context 'when successfully unfollowing a user' do
      let(:destroy_result) { { success: true } }

      before do
        allow(User).to receive(:find).with(user_id).and_return(user)
        allow(Follow).to receive(:find_by).with(user_id: user_id, follower_id: current_user_id).and_return(follow)
        allow(UsersService).to receive(:destroy_follow).with(follow).and_return(destroy_result)
        allow(I18n).to receive(:t).with('success.follows.deleted', name: user.name).and_return('You have unfollowed Test User')

        delete :destroy, params: { user_id: user_id }
      end

      it 'returns http success' do
        expect(response).to have_http_status(:ok)
      end

      it 'returns success message' do
        body = JSON.parse(response.body)
        expect(body['message']).to eq('You have unfollowed Test User')
      end
    end

    context 'when not following the user' do
      before do
        allow(User).to receive(:find).with(user_id).and_return(user)
        allow(Follow).to receive(:find_by).with(user_id: user_id, follower_id: current_user_id).and_return(nil)
        allow(I18n).to receive(:t).with('errors.follows.not_following').and_return('You are not following this user')

        delete :destroy, params: { user_id: user_id }
      end

      it 'returns http not found' do
        expect(response).to have_http_status(:not_found)
      end

      it 'returns error message' do
        body = JSON.parse(response.body)
        expect(body['error']).to eq('You are not following this user')
      end
    end

    context 'when unfollow fails' do
      let(:destroy_result) { { success: false, error: 'Failed to unfollow' } }

      before do
        allow(User).to receive(:find).with(user_id).and_return(user)
        allow(Follow).to receive(:find_by).with(user_id: user_id, follower_id: current_user_id).and_return(follow)
        allow(UsersService).to receive(:destroy_follow).with(follow).and_return(destroy_result)

        delete :destroy, params: { user_id: user_id }
      end

      it 'returns unprocessable entity status' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns error message' do
        body = JSON.parse(response.body)
        expect(body['error']).to eq(destroy_result[:error])
      end
    end
  end

  describe 'authentication' do
    context 'when X-User-ID header is missing' do
      before do
        request.headers['X-User-ID'] = nil
        allow(I18n).to receive(:t).with('errors.follows.unauthorized').and_return('Unauthorized')

        get :followers, params: { user_id: user_id }
      end

      it 'returns unauthorized status' do
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns error message' do
        body = JSON.parse(response.body)
        expect(body['error']).to eq('Unauthorized')
      end
    end
  end
end
