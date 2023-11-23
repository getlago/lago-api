# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Wallets::Create, type: :graphql do
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization, currency: 'EUR') }
  let(:expiration_at) { Time.zone.now + 1.year }

  let(:mutation) do
    <<-GQL
      mutation($input: CreateCustomerWalletInput!) {
        createCustomerWallet(input: $input) {
          id
          name
          rateAmount
          status
          currency
          expirationAt
          recurringTransactionRules { lagoId, ruleType, interval, thresholdCredits, paidCredits, grantedCredits }
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

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
          expirationAt: expiration_at.iso8601,
          currency: 'EUR',
          recurringTransactionRules: [
            {
              ruleType: 'interval',
              interval: 'monthly',
            },
          ],
        },
      },
    )

    result_data = result['data']['createCustomerWallet']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('First Wallet')
      expect(result_data['expirationAt']).to eq(expiration_at.iso8601)
      expect(result_data['recurringTransactionRules'].count).to eq(1)
      expect(result_data['recurringTransactionRules'][0]['lagoId']).to be_present
      expect(result_data['recurringTransactionRules'][0]['ruleType']).to eq('interval')
      expect(result_data['recurringTransactionRules'][0]['interval']).to eq('monthly')
      expect(result_data['recurringTransactionRules'][0]['paidCredits']).to eq('0.0')
      expect(result_data['recurringTransactionRules'][0]['grantedCredits']).to eq('0.0')
    end
  end

  context 'when name is not present' do
    it 'creates a wallet' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: nil,
            rateAmount: '1',
            paidCredits: '0.00',
            grantedCredits: '0.00',
            expirationAt: (Time.zone.now + 1.year).iso8601,
            currency: 'EUR',
          },
        },
      )

      result_data = result['data']['createCustomerWallet']

      aggregate_failures do
        expect(result_data['id']).to be_present
        expect(result_data['name']).to be_nil
      end
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
            expirationAt: (Time.zone.now + 1.year).iso8601,
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
            expirationAt: (Time.zone.now + 1.year).iso8601,
            currency: 'EUR',
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
