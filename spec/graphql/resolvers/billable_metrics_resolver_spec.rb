# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::BillableMetricsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        billableMetrics(limit: 5) {
          collection {
            id
            name
            canBeDeleted
            flatGroups {
              id key value
            }
          }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it 'returns a list of billable metrics' do
    metric = create(:billable_metric, organization: organization)

    group1 = create(:group, billable_metric: metric, key: 'cloud', value: 'aws')
    group2 = create(:group, billable_metric: metric, key: 'region', value: 'usa', parent_group_id: group1.id)

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
    )

    aggregate_failures do
      expect(result['data']['billableMetrics']['collection'].count).to eq(organization.billable_metrics.count)
      expect(result['data']['billableMetrics']['collection'].first['id']).to eq(metric.id)
      expect(result['data']['billableMetrics']['collection'].first['canBeDeleted']).to eq(true)
      expect(result['data']['billableMetrics']['collection'].first['flatGroups']).to eq(
        [{ 'id' => group2.id, 'key' => 'aws', 'value' => 'usa' }],
      )

      expect(result['data']['billableMetrics']['metadata']['currentPage']).to eq(1)
      expect(result['data']['billableMetrics']['metadata']['totalCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(current_user: membership.user, query: query)

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
      )
    end
  end

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query: query,
      )

      expect_graphql_error(
        result: result,
        message: 'Not in organization',
      )
    end
  end
end
