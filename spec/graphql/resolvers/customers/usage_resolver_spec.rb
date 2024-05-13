# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Customers::UsageResolver, type: :graphql do
  let(:required_permission) { 'customers:view' }
  let(:query) do
    <<~GQL
      query($customerId: ID!, $subscriptionId: ID!) {
        customerUsage(customerId: $customerId, subscriptionId: $subscriptionId) {
          fromDatetime
          toDatetime
          currency
          issuingDate
          amountCents
          totalAmountCents
          taxesAmountCents
          chargesUsage {
            billableMetric { name code aggregationType }
            charge { chargeModel }
            filters { id units amountCents invoiceDisplayName values eventsCount }
            units
            amountCents
            groupedUsage {
              amountCents
              units
              eventsCount
              groupedBy
              filters { id units amountCents invoiceDisplayName values eventsCount }
            }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:, rate: 20) }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      started_at: Time.zone.now - 2.years,
    )
  end
  let(:plan) { create(:plan, interval: 'monthly') }

  let(:metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:sum_metric) { create(:sum_billable_metric, organization:) }
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
  let(:standard_charge) do
    create(
      :standard_charge,
      plan: subscription.plan,
      billable_metric: sum_metric,
      properties: {
        amount: 1.to_s,
        grouped_by: ['agent_name'],
      },
    )
  end

  let(:billable_metric_filter) do
    create(:billable_metric_filter, billable_metric: metric, key: 'cloud', values: %w[aws gcp])
  end

  let(:charge_filter) { create(:charge_filter, charge: standard_charge, invoice_display_name: nil) }
  let(:charge_filter_value) do
    create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: ['aws'])
  end

  before do
    subscription
    charge
    tax
    charge_filter_value

    create_list(
      :event,
      4,
      organization:,
      customer:,
      subscription:,
      code: metric.code,
      timestamp: Time.zone.now,
    )

    create_list(
      :event,
      4,
      organization:,
      customer:,
      subscription:,
      code: sum_metric.code,
      timestamp: Time.zone.now,
      properties: {
        agent_name: 'frodo',
        cloud: 'aws',
        item_id: 1,
      },
    )
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires permission', 'customers:view'

  it 'returns the usage for the customer' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        customerId: customer.id,
        subscriptionId: subscription.id,
      },
    )

    usage_response = result['data']['customerUsage']

    aggregate_failures do
      expect(usage_response['fromDatetime']).to eq(Time.current.beginning_of_month.iso8601)
      expect(usage_response['toDatetime']).to eq(Time.current.end_of_month.iso8601)
      expect(usage_response['currency']).to eq('EUR')
      expect(usage_response['issuingDate']).to eq(Time.zone.today.end_of_month.iso8601)
      expect(usage_response['amountCents']).to eq('405')
      expect(usage_response['totalAmountCents']).to eq('486')
      expect(usage_response['taxesAmountCents']).to eq('81')

      charge_usage = usage_response['chargesUsage'].first
      expect(charge_usage['billableMetric']['name']).to eq(metric.name)
      expect(charge_usage['billableMetric']['code']).to eq(metric.code)
      expect(charge_usage['billableMetric']['aggregationType']).to eq('count_agg')
      expect(charge_usage['charge']['chargeModel']).to eq('graduated')
      expect(charge_usage['units']).to eq(4.0)
      expect(charge_usage['amountCents']).to eq('5')

      charge_usage = usage_response['chargesUsage'].last
      expect(charge_usage['billableMetric']['name']).to eq(sum_metric.name)
      expect(charge_usage['billableMetric']['code']).to eq(sum_metric.code)
      expect(charge_usage['billableMetric']['aggregationType']).to eq('sum_agg')
      expect(charge_usage['charge']['chargeModel']).to eq('standard')
      expect(charge_usage['units']).to eq(4.0)
      expect(charge_usage['amountCents']).to eq('400')

      grouped_usage = charge_usage['groupedUsage'].first
      expect(grouped_usage['amountCents']).to eq('400')
      expect(grouped_usage['units']).to eq(4.0)
      expect(grouped_usage['eventsCount']).to eq(4)
      expect(grouped_usage['groupedBy']).to eq({'agent_name' => 'frodo'})
    end
  end

  context 'with filters' do
    let(:cloud_bm_filter) do
      create(:billable_metric_filter, billable_metric: metric, key: 'cloud', values: %w[aws google])
    end

    let(:aws_filter) do
      create(:charge_filter, charge:, properties: {amount: '10'})
    end
    let(:aws_filter_value) do
      create(:charge_filter_value, charge_filter: aws_filter, billable_metric_filter: cloud_bm_filter, values: ['aws'])
    end

    let(:google_filter) do
      create(:charge_filter, charge:, properties: {amount: '20'})
    end
    let(:google_filter_value) do
      create(
        :charge_filter_value,
        charge_filter: google_filter,
        billable_metric_filter: cloud_bm_filter,
        values: ['google'],
      )
    end

    let(:charge) do
      create(
        :standard_charge,
        plan: subscription.plan,
        billable_metric: metric,
        properties: {amount: '0'},
      )
    end

    before do
      aws_filter_value
      google_filter_value

      create_list(
        :event,
        3,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now,
        properties: {cloud: 'aws'},
      )

      create(
        :event,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now,
        properties: {cloud: 'google'},
      )
    end

    it 'returns the filter usage for the customer' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {
          customerId: customer.id,
          subscriptionId: subscription.id,
        },
      )

      charge_usage = result['data']['customerUsage']['chargesUsage'][0]
      filters_usage = charge_usage['filters']

      aggregate_failures do
        expect(charge_usage['units']).to eq(8)
        expect(charge_usage['amountCents']).to eq('5000')
        expect(filters_usage).to contain_exactly(
          {
            'id' => nil,
            'units' => 4,
            'amountCents' => '0',
            'invoiceDisplayName' => nil,
            'values' => {},
            'eventsCount' => 4,
          },
          {
            'id' => aws_filter.id,
            'units' => 3,
            'amountCents' => '3000',
            'invoiceDisplayName' => nil,
            'values' => {
              'cloud' => ['aws'],
            },
            'eventsCount' => 3,
          },
          {
            'id' => google_filter.id,
            'units' => 1,
            'amountCents' => '2000',
            'invoiceDisplayName' => nil,
            'values' => {
              'cloud' => ['google'],
            },
            'eventsCount' => 1,
          },
        )
      end
    end
  end
end
