# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::BillableMetricResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($billableMetricId: ID!) {
        billableMetric(id: $billableMetricId) {
          id name
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) do
    create(:billable_metric, organization: organization)
  end

  it 'returns a single billable metric' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        billableMetricId: billable_metric.id,
      },
    )

    metric_response = result['data']['billableMetric']

    aggregate_failures do
      expect(metric_response['id']).to eq(billable_metric.id)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          billableMetricId: billable_metric.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
      )
    end
  end

  context 'when billable metric is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          billableMetricId: 'foo',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
