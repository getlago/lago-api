# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Wallets::Create, type: :graphql do
  let(:required_permission) { 'wallets:create' }
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
          invoiceRequiresSuccessfulPayment
          recurringTransactionRules {
            lagoId
            method
            trigger
            interval
            thresholdCredits
            paidCredits
            grantedCredits
            targetOngoingBalance
            invoiceRequiresSuccessfulPayment
          }
        }
      }
    GQL
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'wallets:create'

  it 'creates a wallet' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
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
          invoiceRequiresSuccessfulPayment: true,
          recurringTransactionRules: [
            {
              method: 'target',
              trigger: 'interval',
              interval: 'monthly',
              targetOngoingBalance: '0.0',
              invoiceRequiresSuccessfulPayment: true
            }
          ]
        }
      }
    )

    result_data = result['data']['createCustomerWallet']

    aggregate_failures do
      expect(result_data['id']).to be_present
      expect(result_data['name']).to eq('First Wallet')
      expect(result_data['invoiceRequiresSuccessfulPayment']).to eq(true)
      expect(result_data['expirationAt']).to eq(expiration_at.iso8601)
      expect(result_data['recurringTransactionRules'].count).to eq(1)
      expect(result_data['recurringTransactionRules'][0]['lagoId']).to be_present
      expect(result_data['recurringTransactionRules'][0]['method']).to eq('target')
      expect(result_data['recurringTransactionRules'][0]['trigger']).to eq('interval')
      expect(result_data['recurringTransactionRules'][0]['interval']).to eq('monthly')
      expect(result_data['recurringTransactionRules'][0]['paidCredits']).to eq('0.0')
      expect(result_data['recurringTransactionRules'][0]['grantedCredits']).to eq('0.0')
      expect(result_data['recurringTransactionRules'][0]['invoiceRequiresSuccessfulPayment']).to eq(true)
    end
  end

  context 'when name is not present' do
    it 'creates a wallet' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            customerId: customer.id,
            name: nil,
            rateAmount: '1',
            paidCredits: '0.00',
            grantedCredits: '0.00',
            expirationAt: (Time.zone.now + 1.year).iso8601,
            currency: 'EUR'
          }
        }
      )

      result_data = result['data']['createCustomerWallet']

      aggregate_failures do
        expect(result_data['id']).to be_present
        expect(result_data['name']).to be_nil
      end
    end
  end
end
