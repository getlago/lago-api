# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Wallets::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization, currency: 'EUR') }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateCustomerWalletInput!) {
        createCustomerWallet(input: $input) {
          id,
          name,
          rateAmount,
          status,
          currency
        }
      }
    GQL
  end

  it 'create a wallet' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          customerId: customer.id,
          name: 'First Wallet',
          rateAmount: '1',
          paidCredits: '0.00',
          grantedCredits: '0.00',
          expirationDate: (Time.zone.now + 1.year).to_date,
          currency: 'EUR',
        },
      },
    )

    result_data = result['data']['createCustomerWallet']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('First Wallet')
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: 'First Wallet',
            rateAmount: '1',
            paidCredits: '0.00',
            grantedCredits: '0.00',
            expirationDate: (Time.zone.now + 1.year).to_date,
            currency: 'EUR',
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
            customerId: customer.id,
            name: 'First Wallet',
            rateAmount: '1',
            paidCredits: '0.00',
            grantedCredits: '0.00',
            expirationDate: (Time.zone.now + 1.year).to_date,
            currency: 'EUR',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
