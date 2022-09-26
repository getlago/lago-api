# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::CustomerResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($customerId: ID!) {
        customer(id: $customerId) {
          id externalId name currency
          invoices { id invoiceType status }
          subscriptions(status: [active]) { id, status }
          appliedCoupons { id amountCents amountCurrency coupon { id name } }
          appliedAddOns { id amountCents amountCurrency addOn { id name } }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) do
    create(:customer, organization: organization, currency: 'EUR')
  end
  let(:subscription) { create(:subscription, customer: customer) }
  let(:applied_add_on) { create(:applied_add_on, customer: customer) }

  before do
    create_list(:invoice, 2, customer: customer)
    applied_add_on
    subscription
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
      expect(customer_response['appliedAddOns'].count).to eq(1)
      expect(customer_response['currency']).to be_present
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
