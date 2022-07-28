# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::SubscriptionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:plan) { create(:plan, organization: organization) }

  describe 'create' do
    let(:params) do
      {
        customer_id: customer.customer_id,
        plan_code: plan.code,
        name: 'subscription name'
      }
    end

    it 'returns a success' do
      post_with_token(organization, '/api/v1/subscriptions', { subscription: params })

      expect(response).to have_http_status(200)

      result = JSON.parse(response.body, symbolize_names: true)[:subscription]

      expect(result[:lago_id]).to be_present
      expect(result[:customer_id]).to eq(customer.customer_id)
      expect(result[:lago_customer_id]).to eq(customer.id)
      expect(result[:plan_code]).to eq(plan.code)
      expect(result[:status]).to eq('active')
      expect(result[:name]).to eq('subscription name')
      expect(result[:started_at]).to be_present
    end

    context 'with invalid params' do
      let(:params) do
        {
          plan_code: plan.code
        }
      end

      it 'returns an unprocessable_entity error' do
        post_with_token(organization, '/api/v1/subscriptions', { subscription: params })

        expect(response).to have_http_status(422)
      end
    end
  end

  describe 'DELETE /subscriptions/terminate' do
    let(:subscription) { create(:subscription, customer: customer, plan: plan) }

    before { subscription }

    it 'terminates a subscription' do
      delete_with_token(organization, "/api/v1/subscriptions?subscription_id=#{subscription.id}")

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:subscription]

      expect(result[:lago_id]).to eq(subscription.id)
      expect(result[:status]).to eq('terminated')
      expect(result[:terminated_at]).to be_present
    end

    context 'with not existing subscription' do
      it 'returns a not found error' do
        delete_with_token(organization, '/api/v1/subscriptions?subscription_id=123456')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'UPDATE /subscriptions/:id' do
    let(:subscription) { create(:subscription, customer: customer, plan: plan) }
    let(:update_params) { { name: 'subscription name new' } }

    before { subscription }

    it 'updates a subscription' do
      put_with_token(organization, "/api/v1/subscriptions/#{subscription.id}", { subscription: update_params })

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:subscription]

      expect(result[:lago_id]).to eq(subscription.id)
      expect(result[:name]).to eq('subscription name new')
    end

    context 'with not existing subscription' do
      it 'returns an not found error' do
        put_with_token(organization, "/api/v1/subscriptions/invalid", { subscription: update_params })

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
