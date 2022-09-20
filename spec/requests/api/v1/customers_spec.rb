# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::CustomersController, type: :request do
  describe 'create' do
    let(:organization) { create(:organization) }
    let(:create_params) do
      {
        external_id: SecureRandom.uuid,
        name: 'Foo Bar',
        currency: 'EUR',
      }
    end

    it 'returns a success' do
      post_with_token(organization, '/api/v1/customers', { customer: create_params })

      expect(response).to have_http_status(:success)
      expect(json[:customer][:lago_id]).to be_present
      expect(json[:customer][:external_id]).to eq(create_params[:external_id])
      expect(json[:customer][:name]).to eq(create_params[:name])
      expect(json[:customer][:created_at]).to be_present
      expect(json[:customer][:currency]).to eq(create_params[:currency])
    end

    context 'with billing configuration' do
      let(:create_params) do
        {
          external_id: SecureRandom.uuid,
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

        expect(json[:customer][:lago_id]).to be_present
        expect(json[:customer][:external_id]).to eq(create_params[:external_id])

        expect(json[:customer][:billing_configuration]).to be_present
        expect(json[:customer][:billing_configuration][:payment_provider]).to eq('stripe')
        expect(json[:customer][:billing_configuration][:provider_customer_id]).to eq('stripe_id')
      end
    end

    context 'with invalid params' do
      let(:create_params) do
        { name: 'Foo Bar', currency: 'invalid' }
      end

      it 'returns an unprocessable_entity' do
        post_with_token(organization, '/api/v1/customers', { customer: create_params })

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /customers/:customer_id/current_usage' do
    let(:customer) { create(:customer, organization: organization) }
    let(:organization) { create(:organization) }
    let(:subscription) do
      create(
        :subscription,
        plan: plan,
        customer: customer,
        started_at: Time.zone.now - 2.years,
      )
    end
    let(:plan) { create(:plan, interval: 'monthly') }

    let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:charge) do
      create(
        :graduated_charge,
        plan: subscription.plan,
        charge_model: 'graduated',
        billable_metric: billable_metric,
        properties: [
          {
            from_value: 0,
            to_value: nil,
            per_unit_amount: '0.01',
            flat_amount: '0.01',
          },
        ],
      )
    end

    before do
      subscription
      charge

      create_list(
        :event,
        4,
        organization: organization,
        customer: customer,
        subscription: subscription,
        code: billable_metric.code,
        timestamp: Time.zone.now,
      )
    end

    it 'returns the usage for the customer' do
      get_with_token(
        organization,
        "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}",
      )

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:customer_usage][:from_date]).to eq(Time.zone.today.beginning_of_month.iso8601)
        expect(json[:customer_usage][:to_date]).to eq(Time.zone.today.end_of_month.iso8601)
        expect(json[:customer_usage][:issuing_date]).to eq(Time.zone.today.end_of_month.iso8601)
        expect(json[:customer_usage][:amount_cents]).to eq(5)
        expect(json[:customer_usage][:amount_currency]).to eq('EUR')
        expect(json[:customer_usage][:total_amount_cents]).to eq(6)
        expect(json[:customer_usage][:total_amount_currency]).to eq('EUR')
        expect(json[:customer_usage][:vat_amount_cents]).to eq(1)
        expect(json[:customer_usage][:vat_amount_currency]).to eq('EUR')

        charge_usage = json[:customer_usage][:charges_usage].first
        expect(charge_usage[:billable_metric][:name]).to eq(billable_metric.name)
        expect(charge_usage[:billable_metric][:code]).to eq(billable_metric.code)
        expect(charge_usage[:billable_metric][:aggregation_type]).to eq('count_agg')
        expect(charge_usage[:charge][:charge_model]).to eq('graduated')
        expect(charge_usage[:units]).to eq('4.0')
        expect(charge_usage[:amount_cents]).to eq(5)
        expect(charge_usage[:amount_currency]).to eq('EUR')
      end
    end

    context 'when customer does not belongs to the organization' do
      let(:customer) { create(:customer) }

      it 'returns not found' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}",
        )

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /customers' do
    let(:organization) { create(:organization) }

    before do
      create_list(:customer, 2, organization: organization)
    end

    it 'returns all customers from organization' do
      get_with_token(organization, '/api/v1/customers')

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(json[:meta][:total_count]).to eq(2)
      end
    end
  end

  describe 'GET /customers/:customer_id' do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization: organization) }

    before do
      customer
    end

    it 'returns the customer' do
      get_with_token(
        organization,
        "/api/v1/customers/#{customer.external_id}",
      )

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(json[:customer][:lago_id]).to eq(customer.id)
      end
    end

    context 'with not existing external_id' do
      it 'returns a not found error' do
        get_with_token(organization, '/api/v1/customers/foobar')

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
