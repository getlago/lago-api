# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::BaseController, type: :controller do
  controller do
    def index
      render nothing: true
    end

    def create
      params.require(:input).permit(:value)
      render nothing: true
    end
  end

  let(:api_key) { create(:api_key) }

  it 'sets the context source to api' do
    request.headers['Authorization'] = "Bearer #{api_key.value}"

    get :index

    expect(CurrentContext.source).to eq 'api'
  end

  describe 'authenticate' do
    before do
      request.headers['Authorization'] = "Bearer #{token}"
      get :index
    end

    context 'with valid authorization header' do
      context 'when authorization token matching api key' do
        let(:token) { api_key.value }

        it 'returns success response' do
          expect(response).to have_http_status(:success)
        end
      end

      context 'when authorization token matching organization api_key' do
        let(:token) { create(:organization, api_key: 'api_key').api_key }

        it 'returns success response' do
          expect(response).to have_http_status(:success)
        end
      end
    end

    context 'with invalid authentication header' do
      let(:token) { SecureRandom.uuid }

      it 'returns an authentication error' do
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  it 'catches the missing parameters error' do
    request.headers['Authorization'] = "Bearer #{api_key.value}"

    post :create

    expect(response).to have_http_status(:bad_request)

    json = JSON.parse(response.body, symbolize_names: true)
    expect(json[:status]).to eq(400)
    expect(json[:error]).to eq('BadRequest: param is missing or the value is empty: input')
  end
end
