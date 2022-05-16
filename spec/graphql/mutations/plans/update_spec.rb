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
    create_list(:billable_metric, 3, organization: organization)
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
              amountCents: 100,
              amountCurrency: 'USD',
              chargeModel: 'standard',
            },
            {
              billableMetricId: billable_metrics.second.id,
              amountCurrency: 'EUR',
              chargeModel: 'package',
              amountCents: 300,
              freeUnits: 10,
              packageSize: 10,
            },
            {
              billableMetricId: billable_metrics.last.id,
              amountCurrency: 'EUR',
              chargeModel: 'graduated',
              graduatedRanges: [
                {
                  fromValue: 0,
                  toValue: 10,
                  perUnitAmountCents: 2,
                  flatAmountCents: 0,
                },
                {
                  fromValue: 11,
                  toValue: nil,
                  perUnitAmountCents: 3,
                  flatAmountCents: 3,
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
      expect(result_data['charges'].count).to eq(3)
      expect(result_data['charges'][2]['graduatedRanges'].count).to eq(2)
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
