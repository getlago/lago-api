# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::PlanResolver, type: :graphql do
  let(:required_permission) { 'plans:view' }
  let(:query) do
    <<~GQL
      query($planId: ID!) {
        plan(id: $planId) {
          id
          name
          customersCount
          subscriptionsCount
          activeSubscriptionsCount
          draftInvoicesCount
          taxes { id rate }
          charges {
            id
            taxes { id rate }
            properties {
              amount
              groupedBy
              freeUnits
              packageSize
              fixedAmount
              freeUnitsPerEvents
              freeUnitsPerTotalAggregation
              perTransactionMaxAmount
              perTransactionMinAmount
              rate
            }
          }
          minimumCommitment {
            id
            amountCents
            invoiceDisplayName
            taxes { id rate }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }

  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:, plan:) }
  let(:minimum_commitment) { create(:commitment, :minimum_commitment, plan:) }

  before do
    customer
    create_list(:subscription, 2, customer:, plan:)
    minimum_commitment
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'plans:view'

  it 'returns a single plan' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: { planId: plan.id },
    )

    plan_response = result['data']['plan']

    aggregate_failures do
      expect(plan_response['id']).to eq(plan.id)
      expect(plan_response['subscriptionsCount']).to eq(2)
      expect(plan_response['customersCount']).to eq(1)
      expect(plan_response['minimumCommitment']).to include(
        'id' => minimum_commitment.id,
        'amountCents' => minimum_commitment.amount_cents.to_s,
        'invoiceDisplayName' => minimum_commitment.invoice_display_name,
        'taxes' => [],
      )
    end
  end

  context 'when plan is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: { planId: 'foo' },
      )

      expect_graphql_error(
        result:,
        message: 'Resource not found',
      )
    end
  end
end
