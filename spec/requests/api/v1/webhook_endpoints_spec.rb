# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::WebhookEndpointsController, type: :request do
  describe 'create' do
    let(:organization) { create(:organization) }
    let(:create_params) do
      {
        webhook_url: Faker::Internet.url,
        signature_algo: 'jwt',
      }
    end

    it 'returns a success' do
      post_with_token(organization, '/api/v1/webhook_endpoints', { webhook_endpoint: create_params })

      expect(response).to have_http_status(:success)

      aggregate_failures do
        expect(json[:webhook_endpoint][:webhook_url]).to eq(create_params[:webhook_url])
        expect(json[:webhook_endpoint][:signature_algo]).to eq('jwt')
      end
    end
  end

  describe 'GET /webhook_endpoints' do
    let(:organization) { create(:organization) }

    before do
      create_list(:webhook_endpoint, 2, organization:)
    end

    it 'returns all webhook endpoints from organization' do
      get_with_token(organization, '/api/v1/webhook_endpoints')

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(json[:meta][:total_count]).to eq(3)
      end
    end
  end

  describe 'GET /webhook_endpoints/:id' do
    let(:webhook_endpoint) { create(:webhook_endpoint) }
    let(:organization) { webhook_endpoint.organization.reload }

    before do
      webhook_endpoint
    end

    context 'with existing id' do
      it 'returns the customer' do
        get_with_token(
          organization,
          "/api/v1/webhook_endpoints/#{webhook_endpoint.id}",
        )

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(json[:webhook_endpoint][:lago_id]).to eq(webhook_endpoint.id)
        end
      end
    end

    context 'with not existing id' do
      it 'returns a not found error' do
        get_with_token(organization, '/api/v1/webhook_endpoints/foobar')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /webhook_endpoints/:id' do
    let(:webhook_endpoint) { create(:webhook_endpoint) }
    let(:organization) { webhook_endpoint.organization.reload }

    before { webhook_endpoint }

    context 'when webhook endpoint exists' do
      it 'deletes a webhook endpoint' do
        expect { delete_with_token(organization, "/api/v1/webhook_endpoints/#{webhook_endpoint.id}") }
          .to change(WebhookEndpoint, :count).by(-1)
      end

      it 'returns deleted webhook_endpoint' do
        delete_with_token(organization, "/api/v1/webhook_endpoints/#{webhook_endpoint.id}")

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:webhook_endpoint][:lago_id]).to eq(webhook_endpoint.id)
          expect(json[:webhook_endpoint][:webhook_url]).to eq(webhook_endpoint.webhook_url)
        end
      end
    end

    context 'when webhook endpoint does not exist' do
      it 'returns not_found error' do
        delete_with_token(organization, '/api/v1/webhook_endpoints/invalid')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PUT /webhook_endpoints/:id' do
    let(:webhook_endpoint) { create(:webhook_endpoint) }
    let(:organization) { webhook_endpoint.organization.reload }
    let(:update_params) do
      {
        webhook_url: 'http://foo.bar',
        signature_algo: 'hmac',
      }
    end

    before { webhook_endpoint }

    context 'when webhook endpoint exists' do
      it 'updates a webhook endpoint' do
        put_with_token(
          organization,
          "/api/v1/webhook_endpoints/#{webhook_endpoint.id}",
          { webhook_endpoint: update_params },
        )

        aggregate_failures do
          expect(response).to have_http_status(:success)

          expect(json[:webhook_endpoint][:webhook_url]).to eq('http://foo.bar')
          expect(json[:webhook_endpoint][:signature_algo]).to eq('hmac')
        end
      end
    end

    context 'when webhook endpoint does not exist' do
      it 'returns not_found error' do
        put_with_token(
          organization,
          '/api/v1/webhook_endpoints/12345',
          { webhook_endpoint: update_params },
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
