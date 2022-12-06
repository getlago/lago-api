# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::WalletResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($walletId: ID!) {
        wallet(id: $walletId) {
          id name expirationAt
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, status: :active, customer: customer, organization: organization) }
  let(:wallet) { create(:wallet, customer: customer) }

  before { subscription }

  it 'returns a single wallet' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        walletId: wallet.id,
      },
    )

    wallet_response = result['data']['wallet']

    aggregate_failures do
      expect(wallet_response['id']).to eq(wallet.id)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          walletId: wallet.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
      )
    end
  end

  context 'when wallet is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          walletId: 'foo',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
