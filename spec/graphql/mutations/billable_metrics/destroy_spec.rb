# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::BillableMetrics::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization: membership.organization) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyBillableMetricInput!) {
        destroyBillableMetric(input: $input) {
          id
        }
      }
    GQL
  end

  it 'deletes a billable metric' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: { input: { id: billable_metric.id } },
    )

    data = result['data']['destroyBillableMetric']
    expect(data['id']).to eq(billable_metric.id)
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: { input: { id: billable_metric.id } },
      )

      expect_unauthorized_error(result)
    end
  end
end
