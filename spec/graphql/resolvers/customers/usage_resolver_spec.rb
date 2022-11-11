# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::Customers::UsageResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($customerId: ID!, $subscriptionId: ID!) {
        customerUsage(customerId: $customerId, subscriptionId: $subscriptionId) {
          fromDate
          toDate
          issuingDate
          amountCents
          amountCurrency
          totalAmountCents
          totalAmountCurrency
          vatAmountCents
          vatAmountCurrency
          chargesUsage {
            billableMetric { name code aggregationType }
            charge { chargeModel }
            groups { id key value units amountCents }
            units
            amountCents
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:customer) { create(:customer, organization: organization) }
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
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        customerId: customer.id,
        subscriptionId: subscription.id,
      },
    )

    usage_response = result['data']['customerUsage']

    aggregate_failures do
      expect(usage_response['fromDate']).to eq(Time.zone.today.beginning_of_month.iso8601)
      expect(usage_response['toDate']).to eq(Time.zone.today.end_of_month.iso8601)
      expect(usage_response['issuingDate']).to eq(Time.zone.today.end_of_month.iso8601)
      expect(usage_response['amountCents']).to eq('5')
      expect(usage_response['amountCurrency']).to eq('EUR')
      expect(usage_response['totalAmountCents']).to eq('6')
      expect(usage_response['totalAmountCurrency']).to eq('EUR')
      expect(usage_response['vatAmountCents']).to eq('1')
      expect(usage_response['vatAmountCurrency']).to eq('EUR')

      charge_usage = usage_response['chargesUsage'].first
      expect(charge_usage['billableMetric']['name']).to eq(metric.name)
      expect(charge_usage['billableMetric']['code']).to eq(metric.code)
      expect(charge_usage['billableMetric']['aggregationType']).to eq('count_agg')
      expect(charge_usage['charge']['chargeModel']).to eq('graduated')
      expect(charge_usage['units']).to eq(4.0)
      expect(charge_usage['amountCents']).to eq('5')
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
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
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
        expect(groups_usage).to match_array(
          [
            { 'id' => aws.id, 'key' => nil, 'value' => 'aws', 'units' => 3, 'amountCents' => '3000' },
            { 'id' => google.id, 'key' => nil, 'value' => 'google', 'units' => 1, 'amountCents' => '2000' },
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
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
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
        expect(groups_usage).to match_array(
          [
            { 'id' => aws_usa.id, 'key' => 'aws', 'value' => 'usa', 'units' => 2, 'amountCents' => '2000' },
            { 'id' => aws_france.id, 'key' => 'aws', 'value' => 'france', 'units' => 1, 'amountCents' => '2000' },
            { 'id' => google_usa.id, 'key' => 'google', 'value' => 'usa', 'units' => 1, 'amountCents' => '3000' },
          ],
        )
      end
    end
  end
end
