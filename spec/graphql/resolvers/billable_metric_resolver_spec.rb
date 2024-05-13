# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::BillableMetricResolver, type: :graphql do
  subject(:graphql_request) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {billableMetricId: billable_metric.id},
    )
  end

  let(:required_permission) { 'billable_metrics:view' }
  let(:query) do
    <<~GQL
      query($billableMetricId: ID!) {
        billableMetric(id: $billableMetricId) {
          id
          name
          subscriptionsCount
          activeSubscriptionsCount
          draftInvoicesCount
          plansCount
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'billable_metrics:view'

  it 'returns a single billable metric' do
    metric_response = graphql_request['data']['billableMetric']

    aggregate_failures do
      expect(metric_response['id']).to eq(billable_metric.id)
      expect(metric_response['subscriptionsCount']).to eq(0)
      expect(metric_response['activeSubscriptionsCount']).to eq(0)
      expect(metric_response['draftInvoicesCount']).to eq(0)
    end
  end

  it 'returns the count number of active subscriptions' do
    terminated_subscription = create(:subscription, :terminated)
    create(:standard_charge, plan: terminated_subscription.plan, billable_metric:)

    subscription = create(:subscription)
    create(:standard_charge, plan: subscription.plan, billable_metric:)

    metric_response = graphql_request['data']['billableMetric']
    expect(metric_response['subscriptionsCount']).to eq(2)
    expect(metric_response['activeSubscriptionsCount']).to eq(1)
  end

  it 'returns the count number of draft invoices' do
    customer = create(:customer, organization: billable_metric.organization)
    subscription = create(:subscription)
    subscription2 = create(:subscription)
    charge = create(:standard_charge, plan: subscription.plan, billable_metric:)
    charge2 = create(:standard_charge, plan: subscription2.plan, billable_metric:)

    invoice = create(:invoice, customer:, organization: billable_metric.organization)
    create(:fee, invoice:, charge:)

    draft_invoice = create(:invoice, :draft, customer:, organization: billable_metric.organization)
    create(:fee, invoice: draft_invoice, charge: charge2)
    create(:fee, invoice: draft_invoice, charge: charge2)

    metric_response = graphql_request['data']['billableMetric']
    expect(metric_response['draftInvoicesCount']).to eq(1)
  end

  context 'when billable metric is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {billableMetricId: 'foo'},
      )

      expect_graphql_error(result:, message: 'Resource not found')
    end
  end
end
