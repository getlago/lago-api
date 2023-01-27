# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::PlanResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($planId: ID!) {
        plan(id: $planId) {
          id
          name
          customerCount
          activeSubscriptionsCount
          draftInvoicesCount
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }

  before do
    customer
    create_list(:subscription, 2, customer:, plan:)
  end

  it 'returns a single plan' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {
        planId: plan.id,
      },
    )

    plan_response = result['data']['plan']

    aggregate_failures do
      expect(plan_response['id']).to eq(plan.id)
      expect(plan_response['customerCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          planId: plan.id,
        },
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
        variables: {
          planId: 'foo',
        },
      )

      expect_graphql_error(
        result:,
        message: 'Resource not found',
      )
    end
  end
end
