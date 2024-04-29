# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::Wallets::Update, type: :graphql do
  let(:required_permission) { 'wallets:update' }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:expiration_at) { (Time.zone.now + 1.year) }
  let(:recurring_transaction_rule) { create(:recurring_transaction_rule, wallet:) }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateCustomerWalletInput!) {
        updateCustomerWallet(input: $input) {
          id
          name
          status
          expirationAt
          recurringTransactionRules { lagoId, ruleType, interval, thresholdCredits, paidCredits, grantedCredits }
        }
      }
    GQL
  end

  before do
    subscription
    recurring_transaction_rule
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'wallets:update'

  it 'updates a wallet' do
    result = execute_graphql(
      current_organization: organization,
      current_user: membership.user,
      permissions: required_permission,
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
      expect(result_data['expirationAt']).to eq(expiration_at.iso8601)
      expect(result_data['recurringTransactionRules'].count).to eq(1)
      expect(result_data['recurringTransactionRules'][0]['lagoId']).to eq(recurring_transaction_rule.id)
      expect(result_data['recurringTransactionRules'][0]['ruleType']).to eq('interval')
      expect(result_data['recurringTransactionRules'][0]['interval']).to eq('weekly')
      expect(result_data['recurringTransactionRules'][0]['paidCredits']).to eq('22.2')
      expect(result_data['recurringTransactionRules'][0]['grantedCredits']).to eq('22.2')
    end
  end
end
