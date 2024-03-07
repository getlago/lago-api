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
          recurring
          organization { id },
          group
          weightedInterval
          filters { key values }
        }
      }
    GQL
  end

  it 'creates a billable metric' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          name: 'New Metric',
          code: 'new_metric',
          description: 'New metric description',
          aggregationType: 'count_agg',
          recurring: false,
          filters: [
            {
              key: 'region',
              values: %w[usa europe],
            },
          ],
        },
      },
    )

    result_data = result['data']['createBillableMetric']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('New Metric')
      expect(result_data['code']).to eq('new_metric')
      expect(result_data['organization']['id']).to eq(membership.organization_id)
      expect(result_data['aggregationType']).to eq('count_agg')
      expect(result_data['recurring']).to eq(false)
      expect(result_data['group']).to eq({})
      expect(result_data['weightedInterval']).to be_nil
    end
  end

  context 'with group parameter' do
    let(:group) do
      {
        key: 'cloud',
        values: [
          { name: 'AWS', key: 'region', values: %w[usa europe] },
          { name: 'Google', key: 'region', values: ['usa'] },
        ],
      }
    end

    it 'creates billable metric\'s group' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            name: 'New Metric',
            code: 'new_metric',
            description: 'New metric description',
            aggregationType: 'count_agg',
            group:,
          },
        },
      )
      result_data = result['data']['createBillableMetric']

      expect(result_data['group']).to eq(group)
    end
  end

  context 'with invalid group parameter' do
    let(:group) do
      { foo: 'bar' }
    end

    it 'creates billable metric\'s group' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            name: 'New Metric',
            code: 'new_metric',
            description: 'New metric description',
            aggregationType: 'count_agg',
            group:,
          },
        },
      )

      expect_unprocessable_entity(result)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            name: 'New Metric',
            code: 'new_metric',
            description: 'New metric description',
            aggregationType: 'count_agg',
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            name: 'New Metric',
            code: 'new_metric',
            description: 'New metric description',
            aggregationType: 'count_agg',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
