# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::WalletsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($walletId: ID!) {
        walletTransactions(walletId: $walletId, limit: 5, status: settled) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:wallet) { create(:wallet, customer: customer) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet: wallet) }

  before do
    wallet_transaction
  end

  it 'returns a list of wallet transactions' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query: query,
      variables: {
        walletId: wallet.id,
      },
    )

    wallet_transactions_response = result['data']['walletTransactions']

    aggregate_failures do
      expect(wallet_transactions_response['collection'].count).to eq(wallet.wallet_transactions.count)
      expect(wallet_transactions_response['collection'].first['id']).to eq(wallet_transaction.id)

      expect(wallet_transactions_response['metadata']['currentPage']).to eq(1)
      expect(wallet_transactions_response['metadata']['totalCount']).to eq(1)
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

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query: query,
        variables: {
          walletId: wallet.id,
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Not in organization',
      )
    end
  end

  context 'when wallet does not exists' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query: query,
        variables: {
          walletId: '123456',
        },
      )

      expect_graphql_error(
        result: result,
        message: 'Resource not found',
      )
    end
  end
end
