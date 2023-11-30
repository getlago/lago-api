# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::WalletResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($id: ID!) {
        wallet(id: $id) {
          id name status creditsBalance
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }

  before { wallet }

  it 'returns a wallet' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: { id: wallet.id },
    )

    coupon_response = result['data']['wallet']

    aggregate_failures do
      expect(coupon_response['id']).to eq(wallet.id)
      expect(coupon_response['name']).to eq(wallet.name)
      expect(coupon_response['status']).to eq('active')
      expect(coupon_response['creditsBalance']).to eq(0)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: { id: wallet.id },
      )

      expect_graphql_error(result:, message: 'Missing organization id')
    end
  end

  context 'when wallet is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: { id: 'foo' },
      )

      expect_graphql_error(result:, message: 'Resource not found')
    end
  end
end
