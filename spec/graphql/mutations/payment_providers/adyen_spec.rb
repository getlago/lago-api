# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::PaymentProviders::Adyen, type: :graphql do
  let(:membership) { create(:membership) }
  let(:api_key) { 'api_key_123456_abc' }
  let(:hmac_key) { 'hmac_124' }
  let(:live_prefix) { 'test' }
  let(:merchant_account) { 'Merchant1' }

  let(:mutation) do
    <<-GQL
      mutation($input: AddAdyenPaymentProviderInput!) {
        addAdyenPaymentProvider(input: $input) {
          id,
          apiKey,
          hmacKey,
          livePrefix,
          merchantAccount
        }
      }
    GQL
  end

  it 'creates an adyen provider' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          apiKey: api_key,
          hmacKey: hmac_key,
          merchantAccount: merchant_account,
          livePrefix: live_prefix,
        },
      },
    )

    result_data = result['data']['addAdyenPaymentProvider']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['apiKey']).to eq("••••••••…abc")
      expect(result_data['hmacKey']).to eq("••••••••…124")
      expect(result_data['livePrefix']).to eq(live_prefix)
      expect(result_data['merchantAccount']).to eq(merchant_account)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            apiKey: api_key,
            merchantAccount: merchant_account,
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
            apiKey: api_key,
            merchantAccount: merchant_account,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
