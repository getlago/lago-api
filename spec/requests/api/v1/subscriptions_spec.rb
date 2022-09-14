# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::SubscriptionsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:plan) { create(:plan, organization: organization) }

  describe 'create' do
    let(:params) do
      {
        external_customer_id: customer.external_id,
        plan_code: plan.code,
        name: 'subscription name',
        external_id: SecureRandom.uuid,
        billing_time: 'anniversary',
      }
    end

    it 'returns a success' do
      post_with_token(organization, '/api/v1/subscriptions', { subscription: params })

      expect(response).to have_http_status(200)

      result = JSON.parse(response.body, symbolize_names: true)[:subscription]

      expect(result[:lago_id]).to be_present
      expect(result[:external_id]).to be_present
      expect(result[:external_customer_id]).to eq(customer.external_id)
      expect(result[:lago_customer_id]).to eq(customer.id)
      expect(result[:plan_code]).to eq(plan.code)
      expect(result[:status]).to eq('active')
      expect(result[:name]).to eq('subscription name')
      expect(result[:started_at]).to be_present
      expect(result[:billing_time]).to eq('anniversary')
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

  describe 'create_with_override' do
    let(:billable_metric) { create(:billable_metric, organization: organization) }
    let(:standard_charge) { create(:standard_charge, billable_metric: billable_metric) }
    let(:graduated_charge) { create(:graduated_charge, billable_metric: billable_metric) }

    let(:plan) do
      create(:plan, organization: organization, charges: [standard_charge, graduated_charge])
    end

    let(:params) do
      {
        external_customer_id: customer.external_id,
        name: 'subscription name',
        overridden_plan_code: plan.code,
        external_id: SecureRandom.uuid,
        billing_time: 'anniversary',
        plan: {
          amount_cents: 100,
          amount_currency: 'EUR',
          trial_period: 1,
          charges: [
            {
              id: standard_charge.id,
              charge_model: 'standard',
              properties: {
                amount: '0.22',
              },
            },
            {
              id: graduated_charge.id,
              charge_model: 'graduated',
              properties: [
                {
                  to_value: 1,
                  from_value: 0,
                  flat_amount: '0',
                  per_unit_amount: '0',
                },
                {
                  to_value: nil,
                  from_value: 2,
                  flat_amount: '0',
                  per_unit_amount: '3200',
                },
              ],
            },
          ],
        }
      }
    end

    before { plan }

    it 'returns a success' do
      post_with_token(organization, '/api/v1/subscriptions/override', { subscription: params })

      expect(response).to have_http_status(200)

      result = JSON.parse(response.body, symbolize_names: true)[:subscription]

      expect(result[:lago_id]).to be_present
      expect(result[:external_id]).to be_present
      expect(result[:external_customer_id]).to eq(customer.external_id)
      expect(result[:lago_customer_id]).to eq(customer.id)
      expect(result[:plan_code]).not_to eq(plan.code)
      expect(result[:status]).to eq('active')
      expect(result[:name]).to eq('subscription name')
      expect(result[:started_at]).to be_present
      expect(result[:billing_time]).to eq('anniversary')
    end

    it 'creates a new plan' do
      expect do
        post_with_token(organization, '/api/v1/subscriptions/override', { subscription: params })
      end.to change(Plan, :count).by(1)
    end

    context 'with invalid params' do
      let(:params) do
        {
          external_customer_id: customer.external_id,
          name: 'subscription name',
          overridden_plan_code: plan.code,
          external_id: SecureRandom.uuid,
          billing_time: 'anniversary',
          plan: {
            amount_currency: 'EUR',
          }
        }
      end

      it 'returns an unprocessable_entity error' do
        post_with_token(organization, '/api/v1/subscriptions/override', { subscription: params })

        expect(response).to have_http_status(422)
      end
    end
  end

  describe 'delete /subscriptions/:id' do
    let(:subscription) { create(:subscription, customer: customer, plan: plan) }

    before { subscription }

    it 'terminates a subscription' do
      delete_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}")

      expect(response).to have_http_status(:success)

      result = JSON.parse(response.body, symbolize_names: true)[:subscription]

      expect(result[:lago_id]).to eq(subscription.id)
      expect(result[:status]).to eq('terminated')
      expect(result[:terminated_at]).to be_present
    end

    context 'with not existing subscription' do
      it 'returns a not found error' do
        delete_with_token(organization, '/api/v1/subscriptions/123456')

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'update' do
    let(:subscription) { create(:subscription, customer: customer, plan: plan) }
    let(:update_params) { { name: 'subscription name new' } }

    before { subscription }

    it 'updates a subscription' do
      put_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}", { subscription: update_params })

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

  describe 'index' do
    let(:subscription1) { create(:subscription, customer: customer, plan: plan) }

    before { subscription1 }

    it 'returns subscriptions' do
      get_with_token(organization, "/api/v1/subscriptions?external_customer_id=#{customer.external_id}")

      expect(response).to have_http_status(:success)

      records = JSON.parse(response.body, symbolize_names: true)[:subscriptions]

      expect(records.count).to eq(1)
      expect(records.first[:lago_id]).to eq(subscription1.id)
    end

    context 'with pagination' do
      let(:plan2) { create(:plan, organization: organization, amount_cents: 30000) }
      let(:subscription2) { create(:subscription, customer: customer, plan: plan2) }

      before { subscription2 }

      it 'returns subscriptions with correct meta data' do
        get_with_token(organization, "/api/v1/subscriptions?external_customer_id=#{customer.external_id}&page=1&per_page=1")

        expect(response).to have_http_status(:success)

        response_body = JSON.parse(response.body, symbolize_names: true)

        expect(response_body[:subscriptions].count).to eq(1)
        expect(response_body[:meta][:current_page]).to eq(1)
        expect(response_body[:meta][:next_page]).to eq(2)
        expect(response_body[:meta][:prev_page]).to eq(nil)
        expect(response_body[:meta][:total_pages]).to eq(2)
        expect(response_body[:meta][:total_count]).to eq(2)
      end
    end

    context 'with invalid customer' do
      it 'returns not_found error' do
        get_with_token(organization, '/api/v1/subscriptions?external_customer_id=invalid')

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
