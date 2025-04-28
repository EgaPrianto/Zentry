require 'rails_helper'

RSpec.describe SleepEntriesController, type: :controller do
  let(:user_id) { '123456' }
  let(:valid_headers) { { 'X-User-ID' => user_id } }
  let(:invalid_headers) { { 'X-User-ID' => nil } }

  describe 'GET #index' do
    let(:sleep_entries) { [instance_double(SleepEntry), instance_double(SleepEntry)] }
    let(:limit) { 10 }
    let(:offset) { 0 }
    let(:total_count) { 2 }

    context 'with valid authentication' do
      before do
        allow(SleepEntry).to receive_message_chain(:where, :limit, :offset).and_return(sleep_entries)
        allow(SleepEntry).to receive_message_chain(:where, :count).and_return(total_count)

        request.headers.merge!(valid_headers)
        get :index, params: { limit: limit, offset: offset }
      end

      it 'returns a success response' do
        expect(response).to be_successful
      end

      it 'assigns @sleep_entries with proper limit and offset' do
        expect(assigns(:sleep_entries)).to eq(sleep_entries)
      end

      it 'returns proper json structure with meta info' do
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('data')
        expect(json_response).to have_key('meta')
        expect(json_response['meta']['total_count']).to eq(total_count)
        expect(json_response['meta']['limit']).to eq(limit)
        expect(json_response['meta']['offset']).to eq(offset)
      end
    end

    context 'with invalid authentication' do
      before do
        request.headers.merge!(invalid_headers)
        get :index
      end

      it 'returns an unauthorized response' do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET #feed' do
    let(:limit) { 10 }
    let(:offset) { 0 }
    let(:total_count) { 2 }
    let(:mock_results) do
      {
        'hits' => {
          'total' => { 'value' => total_count },
          'hits' => [
            { '_source' => {
                'sleep_entry_id' => '1',
                'user_id' => '456',
                'author_id' => '789',
                'sleep_duration' => 480,
                'created_at' => '2025-04-25T10:00:00Z',
                'updated_at' => '2025-04-25T10:00:00Z'
              }
            },
            { '_source' => {
                'sleep_entry_id' => '2',
                'user_id' => '456',
                'author_id' => '789',
                'sleep_duration' => 400,
                'created_at' => '2025-04-24T10:00:00Z',
                'updated_at' => '2025-04-24T10:00:00Z'
              }
            }
          ]
        }
      }
    end

    context 'with valid authentication' do
      before do
        expected_options = {
          size: limit,
          from: offset,
          last_week: true
        }

        allow(::Elasticsearch::SleepEntryService).to receive(:feed_for_user)
          .with(user_id, hash_including(expected_options))
          .and_return(mock_results)

        request.headers.merge!(valid_headers)
        get :feed, params: { limit: limit, offset: offset }
      end

      it 'returns a success response' do
        expect(response).to be_successful
      end

      it 'calls the ElasticSearch service' do
        expect(::Elasticsearch::SleepEntryService).to have_received(:feed_for_user)
          .with(user_id, hash_including(size: limit))
      end

      it 'returns properly formatted entries' do
        json_response = JSON.parse(response.body)
        expect(json_response['data'].length).to eq(2)
        expect(json_response['data'].first).to include(
          'id' => '1',
          'user_id' => '456',
          'author_id' => '789',
          'sleep_duration' => 480
        )
      end

      it 'returns proper meta information' do
        json_response = JSON.parse(response.body)
        expect(json_response['meta']).to include(
          'total_count' => total_count,
          'limit' => limit,
          'offset' => offset,
          'page' => 1,
          'total_pages' => 1
        )
      end
    end

    context 'with invalid authentication' do
      before do
        request.headers.merge!(invalid_headers)
        get :feed
      end

      it 'returns an unauthorized response' do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET #show' do
    let(:sleep_entry_id) { '123' }
    let(:sleep_entry) { instance_double(SleepEntry) }

    before do
      allow(SleepEntry).to receive(:find).with(sleep_entry_id).and_return(sleep_entry)
    end

    context 'with valid authentication' do
      before do
        request.headers.merge!(valid_headers)
      end

      it 'returns a successful response' do
        get :show, params: { id: sleep_entry_id }
        expect(response).to be_successful
      end

      it 'assigns the requested sleep_entry' do
        get :show, params: { id: sleep_entry_id }
        expect(assigns(:sleep_entry)).to eq(sleep_entry)
      end
    end

    context 'with invalid authentication' do
      before do
        request.headers.merge!(invalid_headers)
        get :show, params: { id: sleep_entry_id }
      end

      it 'returns an unauthorized response' do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST #create' do
    let(:valid_attributes) { { sleep_duration: 480, start_at: '2025-04-27T22:00:00Z' } }

    # Create a more complete mock that can handle URL generation
    let(:created_sleep_entry) do
      instance_double(SleepEntry,
        id: '123',
        to_param: '123',
        to_model: SleepEntry.new,
        model_name: SleepEntry.model_name
      )
    end

    context 'with valid authentication and parameters' do
      before do
        success_result = {
          success: true,
          sleep_entry: created_sleep_entry,
          errors: nil
        }

        allow(SleepEntryService).to receive(:create_sleep_entry)
          .with(user_id, kind_of(ActionController::Parameters))
          .and_return(success_result)

        # Allow URL generation for the mock object
        allow(created_sleep_entry).to receive(:persisted?).and_return(true)

        request.headers.merge!(valid_headers)
      end

      it 'creates a new sleep entry' do
        post :create, params: { sleep_entry: valid_attributes }
        expect(SleepEntryService).to have_received(:create_sleep_entry)
      end

      it 'renders a JSON response with the new sleep_entry' do
        post :create, params: { sleep_entry: valid_attributes }
        expect(response).to have_http_status(:created)
        expect(response.content_type).to include('application/json')
      end
    end

    context 'with valid authentication but invalid parameters' do
      before do
        error_result = {
          success: false,
          sleep_entry: nil,
          errors: ['Sleep duration must be positive']
        }

        allow(SleepEntryService).to receive(:create_sleep_entry)
          .with(user_id, kind_of(ActionController::Parameters))
          .and_return(error_result)

        request.headers.merge!(valid_headers)
        post :create, params: { sleep_entry: { sleep_duration: -10 } }
      end

      it 'renders a JSON response with errors' do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)).to have_key('error')
      end
    end

    context 'with invalid authentication' do
      before do
        request.headers.merge!(invalid_headers)
        post :create, params: { sleep_entry: valid_attributes }
      end

      it 'returns an unauthorized response' do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT #update' do
    let(:sleep_entry_id) { '123' }
    let(:sleep_entry) { instance_double(SleepEntry) }
    let(:update_attributes) { { sleep_duration: 500 } }

    context 'with valid authentication and parameters' do
      before do
        allow(SleepEntry).to receive(:find).with(sleep_entry_id).and_return(sleep_entry)
        allow(sleep_entry).to receive(:update)
          .with(kind_of(ActionController::Parameters))
          .and_return(true)

        request.headers.merge!(valid_headers)
      end

      it 'updates the requested sleep_entry' do
        put :update, params: { id: sleep_entry_id, sleep_entry: update_attributes }
        expect(sleep_entry).to have_received(:update)
      end

      it 'renders a JSON response with the updated sleep_entry' do
        put :update, params: { id: sleep_entry_id, sleep_entry: update_attributes }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('application/json')
      end
    end

    context 'with valid authentication but invalid parameters' do
      before do
        allow(SleepEntry).to receive(:find).with(sleep_entry_id).and_return(sleep_entry)
        allow(sleep_entry).to receive(:update)
          .with(kind_of(ActionController::Parameters))
          .and_return(false)
        allow(sleep_entry).to receive(:errors).and_return(['Invalid sleep duration'])

        request.headers.merge!(valid_headers)
        put :update, params: { id: sleep_entry_id, sleep_entry: update_attributes }
      end

      it 'renders a JSON response with errors' do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)).to have_key('error')
      end
    end

    context 'with invalid authentication' do
      before do
        allow(SleepEntry).to receive(:find).with(sleep_entry_id).and_return(sleep_entry)
        request.headers.merge!(invalid_headers)
        put :update, params: { id: sleep_entry_id, sleep_entry: update_attributes }
      end

      it 'returns an unauthorized response' do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE #destroy' do
    let(:sleep_entry_id) { '123' }
    let(:sleep_entry) { instance_double(SleepEntry) }

    before do
      allow(SleepEntry).to receive(:find).with(sleep_entry_id).and_return(sleep_entry)
    end

    context 'with valid authentication' do
      before do
        allow(sleep_entry).to receive(:destroy!).and_return(true)

        request.headers.merge!(valid_headers)
      end

      it 'destroys the requested sleep_entry' do
        delete :destroy, params: { id: sleep_entry_id }
        expect(sleep_entry).to have_received(:destroy!)
      end

      it 'renders a JSON success response' do
        delete :destroy, params: { id: sleep_entry_id }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to have_key('message')
      end
    end

    context 'with invalid authentication' do
      before do
        request.headers.merge!(invalid_headers)
        delete :destroy, params: { id: sleep_entry_id }
      end

      it 'returns an unauthorized response' do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
