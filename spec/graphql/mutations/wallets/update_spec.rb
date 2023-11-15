# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Wallets::Update, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:expiration_at) { DateTime.parse('2022-01-01 23:59:59') }
  let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateCustomerWalletInput!) {
        updateCustomerWallet(input: $input) {
          id
          name
          status
          expirationAt
          recurringTransactionRules { id, ruleType, interval, thresholdCredits, paidCredits, grantedCredits }
        }
      }
    GQL
  end

  before do
    subscription
    recurring_transaction_rule
  end

  around { |test| lago_premium!(&test) }

  it 'updates a wallet' do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {
          id: wallet.id,
          name: 'New name',
          expirationAt: expiration_at.iso8601,
          recurringTransactionRules: [
            {
              lagoId: recurring_transaction_rule.id,
              ruleType: 'interval',
              interval: 'weekly',
              paidCredits: '22.2',
              grantedCredits: '22.2',
            },
          ],
        },
      },
    )

    result_data = result['data']['updateCustomerWallet']

    aggregate_failures do
      expect(result_data['name']).to eq('New name')
      expect(result_data['status']).to eq('active')
      expect(result_data['expirationAt']).to eq('2022-01-01T23:59:59Z')
      expect(result_data['recurringTransactionRules'].count).to eq(1)
      expect(result_data['recurringTransactionRules'][0]['id']).to eq(recurring_transaction_rule.id)
      expect(result_data['recurringTransactionRules'][0]['ruleType']).to eq('interval')
      expect(result_data['recurringTransactionRules'][0]['interval']).to eq('weekly')
      expect(result_data['recurringTransactionRules'][0]['paidCredits']).to eq(22.2)
      expect(result_data['recurringTransactionRules'][0]['grantedCredits']).to eq(22.2)
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
