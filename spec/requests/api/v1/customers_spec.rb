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

    let(:metric) { create(:billable_metric, aggregation_type: 'count_agg') }
    let(:charge) do
      create(
        :graduated_charge,
        plan: subscription.plan,
        charge_model: 'graduated',
        billable_metric: metric,
        properties: {
          graduated_ranges: [
            {
              from_value: 0,
              to_value: nil,
              per_unit_amount: '0.01',
              flat_amount: '0.01',
            },
          ],
        },
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
        code: metric.code,
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
        expect(charge_usage[:billable_metric][:name]).to eq(metric.name)
        expect(charge_usage[:billable_metric][:code]).to eq(metric.code)
        expect(charge_usage[:billable_metric][:aggregation_type]).to eq('count_agg')
        expect(charge_usage[:charge][:charge_model]).to eq('graduated')
        expect(charge_usage[:units]).to eq('4.0')
        expect(charge_usage[:amount_cents]).to eq(5)
        expect(charge_usage[:amount_currency]).to eq('EUR')
        expect(charge_usage[:groups]).to eq([])
      end
    end

    context 'with one dimension group' do
      let(:aws) { create(:group, billable_metric: metric, key: 'cloud', value: 'aws') }
      let(:google) { create(:group, billable_metric: metric, key: 'cloud', value: 'google') }
      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: metric,
          properties: {},
          group_properties: [
            build(
              :group_property,
              group: aws,
              values: { amount: '10', amount_currency: 'EUR' },
            ),
            build(
              :group_property,
              group: google,
              values: { amount: '20', amount_currency: 'EUR' },
            ),
          ],
        )
      end

      before do
        create_list(
          :event,
          3,
          organization: organization,
          customer: customer,
          subscription: subscription,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'aws' },
        )

        create(
          :event,
          organization: organization,
          customer: customer,
          subscription: subscription,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'google' },
        )
      end

      it 'returns the group usage for the customer' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}",
        )

        charge_usage = json[:customer_usage][:charges_usage].first
        groups_usage = charge_usage[:groups]

        aggregate_failures do
          expect(charge_usage[:units]).to eq('4.0')
          expect(charge_usage[:amount_cents]).to eq(5000)
          expect(groups_usage).to match_array(
            [
              { lago_id: aws.id, key: nil, value: 'aws', units: '3.0', amount_cents: 3000 },
              { lago_id: google.id, key: nil, value: 'google', units: '1.0', amount_cents: 2000 },
            ],
          )
        end
      end
    end

    context 'with two dimensions group' do
      let(:aws) { create(:group, billable_metric: metric, key: 'cloud', value: 'aws') }
      let(:google) { create(:group, billable_metric: metric, key: 'cloud', value: 'google') }
      let(:aws_usa) { create(:group, billable_metric: metric, key: 'region', value: 'usa', parent_group_id: aws.id) }
      let(:aws_france) { create(:group, billable_metric: metric, key: 'region', value: 'france', parent_group_id: aws.id) }
      let(:google_usa) { create(:group, billable_metric: metric, key: 'region', value: 'usa', parent_group_id: google.id) }

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: metric,
          properties: {},
          group_properties: [
            build(
              :group_property,
              group: aws_usa,
              values: { amount: '10', amount_currency: 'EUR' },
            ),
            build(
              :group_property,
              group: aws_france,
              values: { amount: '20', amount_currency: 'EUR' },
            ),
            build(
              :group_property,
              group: google_usa,
              values: { amount: '30', amount_currency: 'EUR' },
            ),
          ],
        )
      end

      before do
        create_list(
          :event,
          2,
          organization: organization,
          customer: customer,
          subscription: subscription,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'aws', region: 'usa' },
        )

        create(
          :event,
          organization: organization,
          customer: customer,
          subscription: subscription,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'aws', region: 'france' },
        )

        create(
          :event,
          organization: organization,
          customer: customer,
          subscription: subscription,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: { cloud: 'google', region: 'usa' },
        )
      end

      it 'returns the group usage for the customer' do
        get_with_token(
          organization,
          "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}",
        )

        charge_usage = json[:customer_usage][:charges_usage].first
        groups_usage = charge_usage[:groups]

        aggregate_failures do
          expect(charge_usage[:units]).to eq('4.0')
          expect(charge_usage[:amount_cents]).to eq(7000)
          expect(groups_usage).to match_array(
            [
              { lago_id: aws_usa.id, key: 'aws', value: 'usa', units: '2.0', amount_cents: 2000 },
              { lago_id: aws_france.id, key: 'aws', value: 'france', units: '1.0', amount_cents: 2000 },
              { lago_id: google_usa.id, key: 'google', value: 'usa', units: '1.0', amount_cents: 3000 },
            ],
          )
        end
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
