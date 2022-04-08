# frozen_string_literal: true

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

  it 'returns a single of customer' do
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
      expect(customer_response['subscriptions'].count).to eq(0)
      expect(customer_response['invoices'].count).to eq(0)
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
end
