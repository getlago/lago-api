# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Plans::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization: organization) }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdatePlanInput!) {
        updatePlan(input: $input) {
          id,
          name,
          code,
          interval,
          payInAdvance,
          amountCents,
          amountCurrency,
          charges {
            id,
            billableMetric { id name code },
            graduatedRanges { fromValue, toValue }
          }
        }
      }
    GQL
  end

  let(:billable_metrics) do
    create_list(:billable_metric, 4, organization: organization)
  end

  it 'updates a plan' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: plan.id,
          name: 'Updated plan',
          code: 'new_plan',
          interval: 'monthly',
          payInAdvance: false,
          amountCents: 200,
          amountCurrency: 'EUR',
          charges: [
            {
              billableMetricId: billable_metrics.first.id,
              amount: '100',
              amountCurrency: 'USD',
              chargeModel: 'standard',
            },
            {
              billableMetricId: billable_metrics.second.id,
              amountCurrency: 'EUR',
              chargeModel: 'package',
              amount: '300',
              freeUnits: 10,
              packageSize: 10,
            },
            {
              billableMetricId: billable_metrics.third.id,
              amountCurrency: 'EUR',
              chargeModel: 'percentage',
              rate: '0.25',
              fixedAmount: '2',
              fixedAmountTarget: 'all_units',
            },
            {
              billableMetricId: billable_metrics.last.id,
              amountCurrency: 'EUR',
              chargeModel: 'graduated',
              graduatedRanges: [
                {
                  fromValue: 0,
                  toValue: 10,
                  perUnitAmount: '2',
                  flatAmount: '0',
                },
                {
                  fromValue: 11,
                  toValue: nil,
                  perUnitAmount: '3',
                  flatAmount: '3',
                },
              ],
            },
          ],
        },
      },
    )

    result_data = result['data']['updatePlan']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('Updated plan')
      expect(result_data['code']).to eq('new_plan')
      expect(result_data['interval']).to eq('monthly')
      expect(result_data['payInAdvance']).to eq(false)
      expect(result_data['amountCents']).to eq(200)
      expect(result_data['amountCurrency']).to eq('EUR')
      expect(result_data['charges'].count).to eq(4)
      expect(result_data['charges'][3]['graduatedRanges'].count).to eq(2)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: plan.id,
            name: 'Updated plan',
            code: 'new_plan',
            interval: 'monthly',
            payInAdvance: false,
            amountCents: 200,
            amountCurrency: 'EUR',
            charges: [],
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
