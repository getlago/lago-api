# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Customers::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:stripe_provider) { create(:stripe_provider, organization: organization) }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateCustomerInput!) {
        createCustomer(input: $input) {
          id,
          name,
          customerId,
          city
          country
          paymentProvider
          stripeCustomer { id, providerCustomerId }
        }
      }
    GQL
  end

  it 'creates a customer' do
    stripe_provider

    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          name: 'John Doe',
          customerId: 'john_doe_2',
          city: 'London',
          country: 'GB',
          paymentProvider: 'stripe',
          stripeCustomer: {
            providerCustomerId: 'cu_12345',
          },
        },
      },
    )

    result_data = result['data']['createCustomer']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('John Doe')
      expect(result_data['customerId']).to eq('john_doe_2')
      expect(result_data['city']).to eq('London')
      expect(result_data['country']).to eq('GB')
      expect(result_data['paymentProvider']).to eq('stripe')
      expect(result_data['stripeCustomer']['id']).to be_present
      expect(result_data['stripeCustomer']['providerCustomerId']).to eq('cu_12345')
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            name: 'John Doe',
            customerId: 'john_doe_2',
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
            name: 'John Doe',
            customerId: 'john_doe_2',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
