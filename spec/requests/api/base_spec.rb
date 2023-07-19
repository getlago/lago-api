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

  let(:organization) { create(:organization) }

  it 'sets the context source to api' do
    request.headers['Authorization'] = "Bearer #{organization.api_key}"

    get :index

    expect(CurrentContext.source).to eq 'api'
  end

  describe 'authenticate' do
    it 'validates the organization api key' do
      request.headers['Authorization'] = "Bearer #{organization.api_key}"

      get :index

      expect(response).to have_http_status(:success)
    end

    context 'without authentication header' do
      it 'returns an authentication error' do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  it 'catches the missing parameters error' do
    request.headers['Authorization'] = "Bearer #{organization.api_key}"

    post :create

    expect(response).to have_http_status(:bad_request)

    json = JSON.parse(response.body, symbolize_names: true)
    expect(json[:status]).to eq(400)
    expect(json[:error]).to eq('BadRequest: param is missing or the value is empty: input')
  end
end
