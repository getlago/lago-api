# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::CustomersController, type: :request do
  describe 'create' do
    let(:organization) { create(:organization) }
    let(:create_params) do
      {
        customer_id: SecureRandom.uuid,
        name: 'Foo Bar'
      }
    end

    it 'returns a success' do
      post_with_token(organization, '/api/v1/customers', { customer: create_params })

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:customer]
      expect(result[:lago_id]).to be_present
      expect(result[:customer_id]).to eq(create_params[:customer_id])
      expect(result[:name]).to eq(create_params[:name])
      expect(result[:created_at]).to be_present
    end

    context 'with billing configuration' do
      let(:create_params) do
        {
          customer_id: SecureRandom.uuid,
          name: 'Foo Bar',
          billing_configuration: {
            payment_provider: 'stripe',
            provider_customer_id: 'stripe_id',
          },
        }
      end

      it 'returns a success' do
        post_with_token(organization, '/api/v1/customers', { customer: create_params })

        expect(response).to have_http_status(:success)

        result = JSON.parse(response.body, symbolize_names: true)[:customer]
        expect(result[:lago_id]).to be_present
        expect(result[:customer_id]).to eq(create_params[:customer_id])

        expect(result[:billing_configuration]).to be_present
        expect(result[:billing_configuration][:payment_provider]).to eq('stripe')
        expect(result[:billing_configuration][:provider_customer_id]).to eq('stripe_id')
      end
    end

    context 'with invalid params' do
      let(:create_params) do
        {
          name: 'Foo Bar'
        }
      end

      it 'returns an unprocessable_entity' do
        post_with_token(organization, '/api/v1/customers', { customer: create_params })

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
