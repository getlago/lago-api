# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::WalletTransactionSerializer do
  subject(:serializer) do
    described_class.new(wallet_transaction, root_name: 'wallet_transaction')
  end

  let(:wallet_transaction) { create(:wallet_transaction) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['wallet_transaction']).to include(
        'lago_id' => wallet_transaction.id,
        'lago_wallet_id' => wallet_transaction.wallet_id,
        'status' => wallet_transaction.status,
        'transaction_status' => wallet_transaction.transaction_status,
        'transaction_type' => wallet_transaction.transaction_type,
        'amount' => wallet_transaction.amount.to_s,
        'credit_amount' => wallet_transaction.credit_amount.to_s,
        'settled_at' => wallet_transaction.settled_at&.iso8601,
        'created_at' => wallet_transaction.created_at.iso8601,
        'invoice_require_successful_payment' => wallet_transaction.invoice_require_successful_payment
      )
    end
  end
end
