# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::BillableMetrics::Destroy, type: :graphql do
  let(:required_permission) { 'billable_metrics:delete' }
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

  it_behaves_like 'requires current user'
  it_behaves_like 'requires permission', 'billable_metrics:delete'

  it 'deletes a billable metric' do
    result = execute_graphql(
      current_user: membership.user,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: billable_metric.id}}
    )

    data = result['data']['destroyBillableMetric']
    expect(data['id']).to eq(billable_metric.id)
  end
end
