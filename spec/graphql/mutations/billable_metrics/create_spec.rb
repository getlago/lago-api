# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::BillableMetrics::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:mutation) do
    <<~GQL
      mutation($input: CreateBillableMetricInput!) {
        createBillableMetric(input: $input) {
          id,
          name,
          code,
          aggregationType,
          organization { id }
        }
      }
    GQL
  end

  it 'creates a billable metric' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          name: 'New Metric',
          code: 'new_metric',
          description: 'New metric description',
          organizationId: membership.organization_id,
          aggregationType: 'count_agg',
          properties: {}
        }
      }
    )

    result_data = result['data']['createBillableMetric']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('New Metric')
      expect(result_data['code']).to eq('new_metric')
      expect(result_data['organization']['id']).to eq(membership.organization_id)
      expect(result_data['aggregationType']).to eq('count_agg')
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            name: 'New Metric',
            code: 'new_metric',
            description: 'New metric description',
            organizationId: membership.organization_id,
            aggregationType: 'count_agg',
            properties: {}
          }
        }
      )

      expect_unauthorized_error(result)
    end
  end
end
