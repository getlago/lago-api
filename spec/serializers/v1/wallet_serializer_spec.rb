# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::WalletSerializer do
  subject(:serializer) { described_class.new(wallet, root_name: 'wallet') }

  let(:wallet) { create(:wallet) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['wallet']['lago_id']).to eq(wallet.id)
      expect(result['wallet']['lago_customer_id']).to eq(wallet.customer_id)
      expect(result['wallet']['external_customer_id']).to eq(wallet.customer.external_id)
      expect(result['wallet']['status']).to eq(wallet.status)
      expect(result['wallet']['currency']).to eq(wallet.currency)
      expect(result['wallet']['name']).to eq(wallet.name)
      expect(result['wallet']['rate_amount']).to eq(wallet.rate_amount.to_s)
      expect(result['wallet']['credits_balance']).to eq(wallet.credits_balance.to_s)
      expect(result['wallet']['balance']).to eq(wallet.balance.to_s)
      expect(result['wallet']['consumed_credits']).to eq(wallet.consumed_credits.to_s)
      expect(result['wallet']['created_at']).to eq(wallet.created_at.iso8601)
      expect(result['wallet']['expiration_at']).to eq(wallet.expiration_at&.iso8601)
      expect(result['wallet']['last_balance_sync_at']).to eq(wallet.last_balance_sync_at&.iso8601)
      expect(result['wallet']['last_consumed_credit_at']).to eq(wallet.last_consumed_credit_at&.iso8601)
      expect(result['wallet']['terminated_at']).to eq(wallet.terminated_at)
    end
  end
end
