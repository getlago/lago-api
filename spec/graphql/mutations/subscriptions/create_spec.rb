# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Plans::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization: organization) }
  let(:customer) { create(:customer, organization: organization) }
  let(:mutation) do
    <<~GQL
      mutation($input: CreateSubscriptionInput!) {
        createSubscription(input: $input) {
          id,
          status,
          startedAt,
          customer {
            id
          },
          plan {
            id
          }
        }
      }
    GQL
  end

  it 'creates a subscription' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          customerId: customer.customer_id,
          planCode: plan.code,
        },
      },
    )

    result_data = result['data']['createSubscription']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['status'].to_sym).to eq(:active)
      expect(result_data['startedAt']).to be_present
      expect(result_data['customer']['id']).to eq(customer.id)
      expect(result_data['plan']['id']).to eq(plan.id)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            customerId: customer.customer_id,
            planCode: plan.code,
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
            customerId: customer.customer_id,
            planCode: plan.code,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
