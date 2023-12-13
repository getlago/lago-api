# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::PaymentProviderResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($paymentProviderId: ID!) {
        paymentProvider(id: $paymentProviderId) {
          ... on AdyenProvider {
              id
              code
              name
              __typename
            }
            ... on GocardlessProvider {
              id
              code
              name
              __typename
            }
            ... on StripeProvider {
              id
              code
              name
              __typename
            }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:stripe_provider) { create(:stripe_provider, organization:) }

  before do
    customer
    stripe_provider
  end

  it 'returns a single payment provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: { paymentProviderId: stripe_provider.id },
    )

    payment_provider_response = result['data']['paymentProvider']

    aggregate_failures do
      expect(payment_provider_response['id']).to eq(stripe_provider.id)
      expect(payment_provider_response['code']).to eq(stripe_provider.code)
      expect(payment_provider_response['name']).to eq(stripe_provider.name)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: { paymentProviderId: stripe_provider.id },
      )

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end

  context 'when payment provider is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: { paymentProviderId: 'foo' },
      )

      expect_graphql_error(
        result:,
        message: 'Resource not found',
      )
    end
  end
end
