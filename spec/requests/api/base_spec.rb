# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::BaseController, type: :controller do
  controller do
    def index
      render nothing: true
    end
  end

  it 'sets the context source to api' do
    get :index

    expect(CurrentContext.source).to eq 'api'
  end

  describe 'authenticate' do
    let(:organization) { create(:organization) }

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
end
