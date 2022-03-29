# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::SubscriptionsController, type: :request do
  describe 'create' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization: organization) }
    let(:plan) { create(:plan, organization: organization) }

    let(:params) do
      {
        customer_id: customer.customer_id,
        plan_code: plan.code
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
end
