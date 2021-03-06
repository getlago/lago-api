# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Customers::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:stripe_provider) { create(:stripe_provider, organization: organization) }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateCustomerInput!) {
        updateCustomer(input: $input) {
          id,
          name,
          customerId
          paymentProvider
          stripeCustomer { id, providerCustomerId }
        }
      }
    GQL
  end

  it 'updates a customer' do
    stripe_provider
    customer_id = SecureRandom.uuid

    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: customer.id,
          name: 'Updated customer',
          customerId: customer_id,
          paymentProvider: 'stripe',
          stripeCustomer: {
            providerCustomerId: 'cu_12345',
          },
        },
      },
    )

    result_data = result['data']['updateCustomer']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('Updated customer')
      expect(result_data['customerId']).to eq(customer_id)
      expect(result_data['paymentProvider']).to eq('stripe')
      expect(result_data['stripeCustomer']['id']).to be_present
      expect(result_data['stripeCustomer']['providerCustomerId']).to eq('cu_12345')
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: customer.id,
            name: 'Updated customer',
            customerId: SecureRandom.uuid,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
