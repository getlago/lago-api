# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::WalletSerializer do
  subject(:serializer) { described_class.new(wallet, root_name: 'wallet') }

  let(:wallet) { create(:wallet) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['wallet']).to include(
        'lago_id' => wallet.id,
        'lago_customer_id' => wallet.customer_id,
        'external_customer_id' => wallet.customer.external_id,
        'status' => wallet.status,
        'currency' => wallet.currency,
        'name' => wallet.name,
        'rate_amount' => wallet.rate_amount.to_s,
        'created_at' => wallet.created_at.iso8601,
        'expiration_at' => wallet.expiration_at&.iso8601,
        'last_balance_sync_at' => wallet.last_balance_sync_at&.iso8601,
        'last_consumed_credit_at' => wallet.last_consumed_credit_at&.iso8601,
        'terminated_at' => wallet.terminated_at,
        'credits_balance' => wallet.credits_balance.to_s,
        'balance_cents' => wallet.balance_cents,
        'credits_ongoing_balance' => wallet.credits_ongoing_balance.to_s,
        'credits_ongoing_usage_balance' => wallet.credits_ongoing_usage_balance.to_s,
        'ongoing_balance_cents' => wallet.ongoing_balance_cents,
        'ongoing_usage_balance_cents' => wallet.ongoing_usage_balance_cents,
        'consumed_credits' => wallet.consumed_credits.to_s
      )
    end
  end
end
