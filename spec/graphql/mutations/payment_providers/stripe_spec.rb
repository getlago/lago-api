# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::PaymentProviders::Stripe, type: :graphql do
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: AddStripePaymentProviderInput!) {
        addStripePaymentProvider(input: $input) {
          id,
          secretKey
          createCustomers
        }
      }
    GQL
  end

  let(:secret_key) { 'sk_12345678901234567890' }

  it 'creates a stripe provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          secretKey: secret_key,
          createCustomers: false,
        },
      },
    )

    result_data = result['data']['addStripePaymentProvider']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['secretKey']).to eq('••••••••…890')
      expect(result_data['createCustomers']).to eq(false)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            secretKey: secret_key,
            createCustomers: false,
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
            secretKey: secret_key,
            createCustomers: false,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
