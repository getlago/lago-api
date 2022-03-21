# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::BillableMetrics::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:billable_metric) { create(:billable_metric, organization: membership.organization) }
  let(:mutation) do
    <<-GQL
      mutation($input: UpdateBillableMetricInput!) {
        updateBillableMetric(input: $input) {
          id,
          name,
          code,
          aggregationType,
          billablePeriod,
          organization { id }
        }
      }
    GQL
  end

  it 'updates a billable metric' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: billable_metric.id,
          name: 'New Metric',
          code: 'new_metric',
          description: 'New metric description',
          aggregationType: 'count_agg',
          billablePeriod: 'recurring',
          properties: {}
        }
      }
    )

    result_data = result['data']['updateBillableMetric']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('New Metric')
      expect(result_data['code']).to eq('new_metric')
      expect(result_data['organization']['id']).to eq(membership.organization_id)
      expect(result_data['aggregationType']).to eq('count_agg')
      expect(result_data['billablePeriod']).to eq('recurring')
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: billable_metric.id,
            name: 'New Metric',
            code: 'new_metric',
            description: 'New metric description',
            aggregationType: 'count_agg',
            billablePeriod: 'recurring',
            properties: {}
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
