# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Customers::UsageResolver, type: :graphql do
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
            groups { id key value units amountCents }
            filters { id units amountCents invoiceDisplayName values eventsCount }
            units
            amountCents
            groupedUsage {
              amountCents
              units
              eventsCount
              groupedBy
              groups { id key value units amountCents }
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

  it 'returns the usage for the customer' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
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
      expect(grouped_usage['groupedBy']).to eq({ 'agent_name' => 'frodo' })
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
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now,
        properties: { cloud: 'aws' },
      )

      create(
        :event,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now,
        properties: { cloud: 'google' },
      )
    end

    it 'returns the group usage for the customer' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {
          customerId: customer.id,
          subscriptionId: subscription.id,
        },
      )

      charge_usage = result['data']['customerUsage']['chargesUsage'][0]
      groups_usage = charge_usage['groups']

      aggregate_failures do
        expect(charge_usage['units']).to eq(4)
        expect(charge_usage['amountCents']).to eq('5000')
        expect(groups_usage).to contain_exactly(
          {
            'id' => aws.id,
            'key' => 'cloud',
            'value' => 'aws',
            'units' => 3,
            'amountCents' => '3000',
          },
          { 'id' => google.id, 'key' => 'cloud', 'value' => 'google', 'units' => 1, 'amountCents' => '2000' },
        )
      end
    end
  end

  context 'with two dimensions group' do
    let(:aws) { create(:group, billable_metric: metric, key: 'cloud', value: 'aws') }
    let(:google) { create(:group, billable_metric: metric, key: 'cloud', value: 'google') }
    let(:aws_usa) { create(:group, billable_metric: metric, key: 'region', value: 'usa', parent_group_id: aws.id) }
    let(:aws_france) do
      create(:group, billable_metric: metric, key: 'region', value: 'france', parent_group_id: aws.id)
    end
    let(:google_usa) do
      create(:group, billable_metric: metric, key: 'region', value: 'usa', parent_group_id: google.id)
    end

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
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now,
        properties: { cloud: 'aws', region: 'usa' },
      )

      create(
        :event,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now,
        properties: { cloud: 'aws', region: 'france' },
      )

      create(
        :event,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now,
        properties: { cloud: 'google', region: 'usa' },
      )
    end

    it 'returns the group usage for the customer' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: {
          customerId: customer.id,
          subscriptionId: subscription.id,
        },
      )

      charge_usage = result['data']['customerUsage']['chargesUsage'][0]
      groups_usage = charge_usage['groups']

      aggregate_failures do
        expect(charge_usage['units']).to eq(4)
        expect(charge_usage['amountCents']).to eq('7000')
        expect(groups_usage).to contain_exactly(
          {
            'id' => aws_usa.id,
            'key' => 'aws',
            'value' => 'usa',
            'units' => 2,
            'amountCents' => '2000',
          },
          { 'id' => aws_france.id, 'key' => 'aws', 'value' => 'france', 'units' => 1, 'amountCents' => '2000' },
          { 'id' => google_usa.id, 'key' => 'google', 'value' => 'usa', 'units' => 1, 'amountCents' => '3000' },
        )
      end
    end
  end
end
