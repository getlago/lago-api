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
            group { id key value }
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

  let(:billable_metric) { create(:billable_metric, aggregation_type: 'count_agg') }
  let(:charge) do
    create(
      :graduated_charge,
      plan: subscription.plan,
      charge_model: 'graduated',
      billable_metric: billable_metric,
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
      code: billable_metric.code,
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
      expect(charge_usage['billableMetric']['name']).to eq(billable_metric.name)
      expect(charge_usage['billableMetric']['code']).to eq(billable_metric.code)
      expect(charge_usage['billableMetric']['aggregationType']).to eq('count_agg')
      expect(charge_usage['charge']['chargeModel']).to eq('graduated')
      expect(charge_usage['units']).to eq(4.0)
      expect(charge_usage['amountCents']).to eq('5')
    end
  end

  context 'when fee is linked to a group' do
    it 'returns the group usage for the customer' do
      group = create(:group, billable_metric: billable_metric)
      create(
        :group_property,
        charge: charge,
        group: group,
        values: {
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

      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          customerId: customer.id,
          subscriptionId: subscription.id,
        },
      )

      group_usage = result['data']['customerUsage']['chargesUsage'][0]['group']
      aggregate_failures do
        expect(group_usage['id']).to eq(group.id)
        expect(group_usage['key']).to be_nil
        expect(group_usage['value']).to eq(group.value)
      end
    end
  end
end
