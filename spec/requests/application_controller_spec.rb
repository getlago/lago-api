# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationController, type: :request do
  describe 'GET /health' do
    it 'returns the application health check' do
      get '/health'

      aggregate_failures do
        expect(response.status).to be(200)
        expect(json[:message]).to eq('Success')
        expect(json[:version]).to be_present
        expect(json[:github_url]).to be_present
      end
    end
  end

  describe 'Missing resources' do
    it 'returns a 404 response' do
      get '/not_found'

      aggregate_failures do
        expect(response.status).to be(404)
        expect(json[:status]).to eq(404)
        expect(json[:error]).to eq('Not Found')
        expect(json[:code]).to eq('resource_not_found')
      end
    end
  end
end
