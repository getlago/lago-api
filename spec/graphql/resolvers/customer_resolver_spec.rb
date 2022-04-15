# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CustomerResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($customerId: ID!) {
        customer(id: $customerId) {
          id customerId name
          invoices { id }
          subscriptions { id }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) do
    create(:customer, organization: organization)
  end
  let(:subscription) { create(:subscription, customer: customer) }

  before do
    create_list(:invoice, 2, subscription: subscription)
  end

  it 'returns a single customer' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        customerId: customer.id,
      },
    )

    customer_response = result['data']['customer']

    aggregate_failures do
      expect(customer_response['id']).to eq(customer.id)
      expect(customer_response['subscriptions'].count).to eq(1)
      expect(customer_response['invoices'].count).to eq(2)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          customerId: customer.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
      )
    end
  end

  context 'when customer is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          customerId: 'foo',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
