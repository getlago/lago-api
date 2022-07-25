# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Wallets::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:wallet) { create(:wallet, customer: customer) }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateCustomerWalletInput!) {
        updateCustomerWallet(input: $input) {
          id,
          name,
          status,
          expirationDate,
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
          expirationDate: '2022-01-01',
        },
      },
    )

    result_data = result['data']['updateCustomerWallet']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
      expect(result_data['status']).to eq('active')
      expect(result_data['expirationDate']).to eq('2022-01-01')
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
