# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Wallets::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:wallet) { create(:wallet, customer: customer) }
  let(:expiration_at) { DateTime.parse('2022-01-01 23:59:59') }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateCustomerWalletInput!) {
        updateCustomerWallet(input: $input) {
          id,
          name,
          status,
          expirationAt,
        }
      }
    GQL
  end

  before { subscription }

  it 'updates a wallet' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: wallet.id,
          name: 'New name',
          expirationAt: expiration_at.iso8601,
        },
      },
    )

    result_data = result['data']['updateCustomerWallet']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
      expect(result_data['status']).to eq('active')
      expect(result_data['expirationAt']).to eq('2022-01-01T23:59:59Z')
    end
  end

  context 'without current_user' do
    it 'returns an error' do
      result = execute_graphql(
        query: mutation,
        variables: {
          input: {
            id: wallet.id,
            name: 'New name',
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end
end
