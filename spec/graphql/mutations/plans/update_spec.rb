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
          frequency,
          billingPeriod,
          proRata,
          amountCents,
          amountCurrency,
          billableMetrics { id, name }
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
          frequency: 'monthly',
          billingPeriod: 'end_of_month',
          proRata: false,
          amountCents: 200,
          amountCurrency: 'EUR',
          billableMetricIds: billable_metrics.map(&:id)
        }
      }
    )

    result_data = result['data']['updatePlan']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('Updated plan')
      expect(result_data['code']).to eq('new_plan')
      expect(result_data['frequency']).to eq('monthly')
      expect(result_data['billingPeriod']).to eq('end_of_month')
      expect(result_data['proRata']).to eq(false)
      expect(result_data['amountCents']).to eq(200)
      expect(result_data['amountCurrency']).to eq('EUR')
      expect(result_data['billableMetrics'].count).to eq(4)
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
            frequency: 'monthly',
            billingPeriod: 'end_of_month',
            proRata: false,
            amountCents: 200,
            amountCurrency: 'EUR',
            billableMetricIds: billable_metrics.map(&:id)
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
