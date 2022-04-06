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
          frequency,
          proRata,
          payInAdvance,
          amountCents,
          amountCurrency,
          charges { id, billableMetric { id name code } }
        }
      }
    GQL
  end

  let(:billable_metrics) do
    create_list(:billable_metric, 2, organization: organization)
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
          frequency: 'beginning_of_period',
          proRata: false,
          payInAdvance: false,
          amountCents: 200,
          amountCurrency: 'EUR',
          charges: [
            {
              billableMetricId: billable_metrics.first.id,
              amountCents: 100,
              amountCurrency: 'USD',
              frequency: 'recurring',
              proRata: false,
              chargeModel: 'standard',
            },
            {
              billableMetricId: billable_metrics.last.id,
              amountCents: 300,
              amountCurrency: 'EUR',
              frequency: 'one_time',
              proRata: true,
              vatRate: 10.5,
              chargeModel: 'standard',
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
      expect(result_data['frequency']).to eq('beginning_of_period')
      expect(result_data['proRata']).to eq(false)
      expect(result_data['payInAdvance']).to eq(false)
      expect(result_data['amountCents']).to eq(200)
      expect(result_data['amountCurrency']).to eq('EUR')
      expect(result_data['charges'].count).to eq(2)
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
            frequency: 'beginning_of_period',
            proRata: false,
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
