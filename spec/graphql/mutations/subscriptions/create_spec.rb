# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Subscriptions::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:ending_at) { Time.current.beginning_of_day + 1.year }
  let(:customer) { create(:customer, organization:) }
  let(:mutation) do
    <<~GQL
      mutation($input: CreateSubscriptionInput!) {
        createSubscription(input: $input) {
          id
          status
          name
          externalId
          startedAt
          billingTime
          subscriptionAt
          endingAt
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
          customerId: customer.id,
          planId: plan.id,
          name: 'invoice display name',
          externalId: 'custom-external-id',
          billingTime: 'anniversary',
          endingAt: ending_at.iso8601,
        },
      },
    )

    result_data = result['data']['createSubscription']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['status'].to_sym).to eq(:active)
      expect(result_data['name']).to eq('invoice display name')
      expect(result_data['externalId']).to eq('custom-external-id')
      expect(result_data['startedAt']).to be_present
      expect(result_data['customer']['id']).to eq(customer.id)
      expect(result_data['plan']['id']).to eq(plan.id)
      expect(result_data['billingTime']).to eq('anniversary')
      expect(result_data['endingAt']).to eq(ending_at.iso8601)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            planId: plan.id,
            billingTime: 'anniversary',
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
            customerId: customer.id,
            planId: plan.id,
            billingTime: 'anniversary',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
