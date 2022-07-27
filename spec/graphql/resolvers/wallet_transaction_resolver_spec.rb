# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::WalletTransactionResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($walletTransactionId: ID!) {
        walletTransaction(id: $walletTransactionId) {
          id, amount, creditAmount
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization) }
  let(:wallet) { create(:wallet, customer: customer) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet: wallet) }

  before { wallet_transaction }

  it 'returns a single wallet transaction' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: query,
      variables: {
        walletTransactionId: wallet_transaction.id,
      },
    )
    
    wallet_transaction_response = result['data']['walletTransaction']

    aggregate_failures do
      expect(wallet_transaction_response['id']).to eq(wallet_transaction.id)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: query,
        variables: {
          walletTransactionId: wallet_transaction.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Missing organization id',
      )
    end
  end

  context 'when wallet transaction is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: query,
        variables: {
          walletTransactionId: 'foo',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
