# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::PlanResolver, type: :graphql do
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
            groupProperties {
              groupId
              invoiceDisplayName
              values {
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
              deletedAt
            }
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:group) { create(:group, billable_metric:) }
  let(:group_property) { create(:group_property, group:, charge:) }

  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, billable_metric:, plan:) }

  before do
    customer
    group_property
    create_list(:subscription, 2, customer:, plan:)
  end

  it 'returns a single plan' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: { planId: plan.id },
    )

    plan_response = result['data']['plan']

    aggregate_failures do
      expect(plan_response['id']).to eq(plan.id)
      expect(plan_response['subscriptionsCount']).to eq(2)
      expect(plan_response['customersCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: { planId: plan.id },
      )

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end

  context 'when plan is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
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
