# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Customers::UsageController, type: :request do
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }

  let(:plan) { create(:plan, interval: 'monthly') }

  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      started_at: Time.zone.now - 2.years
    )
  end

  describe 'GET /customers/:customer_id/current_usage' do
    let(:tax) { create(:tax, organization:, rate: 20) }

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
              flat_amount: '0.01'
            }
          ]
        }
      )
    end

    let(:path) do
      [
        '/api/v1/customers',
        customer.external_id,
        "current_usage?external_subscription_id=#{subscription.external_id}"
      ].join('/')
    end

    before do
      subscription
      charge
      tax

      create_list(
        :event,
        4,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now
      )
    end

    it 'returns the usage for the customer' do
      get_with_token(organization, path)

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:customer_usage][:from_datetime]).to eq(Time.zone.today.beginning_of_month.beginning_of_day.iso8601)
        expect(json[:customer_usage][:to_datetime]).to eq(Time.zone.today.end_of_month.end_of_day.iso8601)
        expect(json[:customer_usage][:issuing_date]).to eq(Time.zone.today.end_of_month.iso8601)
        expect(json[:customer_usage][:amount_cents]).to eq(5)
        expect(json[:customer_usage][:currency]).to eq('EUR')
        expect(json[:customer_usage][:total_amount_cents]).to eq(6)

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

    context 'with filters' do
      let(:billable_metric_filter) do
        create(:billable_metric_filter, billable_metric: metric, key: 'cloud', values: %w[aws google])
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: metric,
          properties: {amount: '0'}
        )
      end

      let(:charge_filter_aws) { create(:charge_filter, charge:, properties: {amount: '10'}) }
      let(:charge_filter_gcp) { create(:charge_filter, charge:, properties: {amount: '20'}) }

      let(:charge_filter_value_aws) do
        create(:charge_filter_value, charge_filter: charge_filter_aws, billable_metric_filter:, values: ['aws'])
      end

      let(:charge_filter_value_gcp) do
        create(:charge_filter_value, charge_filter: charge_filter_gcp, billable_metric_filter:, values: ['google'])
      end

      before do
        charge_filter_value_aws
        charge_filter_value_gcp

        create_list(
          :event,
          3,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: 'aws'}
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: 'google'}
        )
      end

      it 'returns the group usage for the customer' do
        get_with_token(organization, path)

        charge_usage = json[:customer_usage][:charges_usage].first
        groups_usage = charge_usage[:groups]

        aggregate_failures do
          expect(charge_usage[:units]).to eq('8.0')
          expect(charge_usage[:amount_cents]).to eq(5000)
          expect(groups_usage).to contain_exactly(
            {
              lago_id: "charge-filter-#{charge_filter_aws.id}",
              key: 'cloud',
              value: 'aws',
              units: '3.0',
              amount_cents: 3000,
              events_count: 3
            },
            {
              lago_id: "charge-filter-#{charge_filter_gcp.id}",
              key: 'cloud',
              value: 'google',
              units: '1.0',
              amount_cents: 2000,
              events_count: 1
            }
          )
        end
      end
    end

    context 'with multiple filter values' do
      let(:billable_metric_filter_cloud) do
        create(:billable_metric_filter, billable_metric: metric, key: 'cloud', values: %w[aws google])
      end
      let(:billable_metric_filter_region) do
        create(:billable_metric_filter, billable_metric: metric, key: 'region', values: %w[usa france])
      end

      let(:charge_filter_aws_usa) { create(:charge_filter, charge:, properties: {amount: '10'}) }
      let(:charge_filter_aws_france) { create(:charge_filter, charge:, properties: {amount: '20'}) }
      let(:charge_filter_google_usa) { create(:charge_filter, charge:, properties: {amount: '30'}) }

      let(:charge_filter_value11) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_aws_usa,
          billable_metric_filter: billable_metric_filter_cloud,
          values: ['aws']
        )
      end
      let(:charge_filter_value12) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_aws_usa,
          billable_metric_filter: billable_metric_filter_region,
          values: ['usa']
        )
      end

      let(:charge_filter_value21) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_aws_france,
          billable_metric_filter: billable_metric_filter_cloud,
          values: ['aws']
        )
      end
      let(:charge_filter_value22) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_aws_france,
          billable_metric_filter: billable_metric_filter_region,
          values: ['france']
        )
      end

      let(:charge_filter_value31) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_google_usa,
          billable_metric_filter: billable_metric_filter_cloud,
          values: ['google']
        )
      end
      let(:charge_filter_value32) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_google_usa,
          billable_metric_filter: billable_metric_filter_region,
          values: ['usa']
        )
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: metric,
          properties: {amount: '0'}
        )
      end

      before do
        charge_filter_value11
        charge_filter_value12
        charge_filter_value21
        charge_filter_value22
        charge_filter_value31
        charge_filter_value32

        create_list(
          :event,
          2,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: 'aws', region: 'usa'}
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: 'aws', region: 'france'}
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: 'google', region: 'usa'}
        )
      end

      it 'returns the group usage for the customer' do
        get_with_token(organization, path)

        charge_usage = json[:customer_usage][:charges_usage].first
        groups_usage = charge_usage[:groups]

        aggregate_failures do
          expect(charge_usage[:units]).to eq('8.0')
          expect(charge_usage[:amount_cents]).to eq(7000)
          expect(groups_usage).to contain_exactly(
            {
              lago_id: "charge-filter-#{charge_filter_aws_usa.id}",
              key: 'cloud, region',
              value: 'aws, usa',
              units: '2.0',
              amount_cents: 2000,
              events_count: 2
            },
            {
              lago_id: "charge-filter-#{charge_filter_aws_france.id}",
              key: 'cloud, region',
              value: 'aws, france',
              units: '1.0',
              amount_cents: 2000,
              events_count: 1
            },
            {
              lago_id: "charge-filter-#{charge_filter_google_usa.id}",
              key: 'cloud, region',
              value: 'google, usa',
              units: '1.0',
              amount_cents: 3000,
              events_count: 1
            }
          )
        end
      end
    end

    context 'when customer does not belongs to the organization' do
      let(:customer) { create(:customer) }

      it 'returns not found' do
        get_with_token(organization, path)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /customers/:customer_id/past_usage' do
    let(:invoice_subscription) do
      create(
        :invoice_subscription,
        charges_from_datetime: DateTime.parse('2023-08-17T00:00:00'),
        charges_to_datetime: DateTime.parse('2023-09-16T23:59:59'),
        subscription:
      )
    end

    let(:billable_metric1) { create(:billable_metric, organization:) }
    let(:billable_metric2) { create(:billable_metric, organization:) }

    let(:charge1) { create(:standard_charge, plan:, billable_metric: billable_metric1) }
    let(:charge2) { create(:standard_charge, plan:, billable_metric: billable_metric2) }

    let(:invoice) { invoice_subscription.invoice }

    let(:fee1) { create(:charge_fee, charge: charge1, invoice:) }
    let(:fee2) { create(:charge_fee, charge: charge2, invoice:) }

    let(:path) do
      [
        '/api/v1/customers',
        customer.external_id,
        "past_usage?external_subscription_id=#{subscription.external_id}&periods_count=2"
      ].join('/')
    end

    before do
      fee1
      fee2
    end

    it 'returns the past usage' do
      get_with_token(organization, path)

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:usage_periods].count).to eq(1)

        usage = json[:usage_periods].first
        expect(usage[:from_datetime]).to eq(invoice_subscription.charges_from_datetime.iso8601)
        expect(usage[:to_datetime]).to eq(invoice_subscription.charges_to_datetime.iso8601)
        expect(usage[:issuing_date]).to eq(invoice.issuing_date.iso8601)
        expect(usage[:currency]).to eq(invoice.currency)
        expect(usage[:amount_cents]).to eq(invoice.fees_amount_cents)
        expect(usage[:total_amount_cents]).to eq(4)
        expect(usage[:taxes_amount_cents]).to eq(4)

        expect(usage[:charges_usage].count).to eq(2)

        charge_usage = usage[:charges_usage].first
        expect(charge_usage[:billable_metric][:name]).to eq(billable_metric1.name)
        expect(charge_usage[:billable_metric][:code]).to eq(billable_metric1.code)
        expect(charge_usage[:billable_metric][:aggregation_type]).to eq(billable_metric1.aggregation_type)
        expect(charge_usage[:charge][:charge_model]).to eq(charge1.charge_model)
        expect(charge_usage[:units]).to eq(fee1.units.to_s)
        expect(charge_usage[:amount_cents]).to eq(fee1.amount_cents)
        expect(charge_usage[:amount_currency]).to eq(fee1.currency)
        expect(charge_usage[:groups]).to eq([])
      end
    end

    context 'when missing external_subscription_id' do
      let(:path) do
        [
          '/api/v1/customers',
          customer.external_id,
          'past_usage'
        ].join('/')
      end

      it 'returns an unprocessable entity' do
        get_with_token(organization, path)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with invalid billable metric code' do
      let(:path) do
        [
          '/api/v1/customers',
          customer.external_id,
          "past_usage?billable_metric_code=foo&external_subscription_id=#{subscription.external_id}"
        ].join('/')
      end

      it 'returns a not found error' do
        get_with_token(organization, path)

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
