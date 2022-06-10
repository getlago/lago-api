# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::PaymentProviders::Stripe, type: :graphql do
  let(:membership) { create(:membership) }

  let(:mutation) do
    <<-GQL
      mutation($input: AddStripePaymentProviderInput!) {
        addStripePaymentProvider(input: $input) {
          id,
          publicKey
        }
      }
    GQL
  end

  let(:public_key) { SecureRandom.uuid }
  let(:secret_key) { SecureRandom.uuid }

  it 'creates a stripe provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          publicKey: public_key,
          secretKey: secret_key,
        },
      },
    )

    result_data = result['data']['addStripePaymentProvider']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['publicKey']).to eq(public_key)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            publicKey: public_key,
            secretKey: secret_key,
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
            publicKey: public_key,
            secretKey: secret_key,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
