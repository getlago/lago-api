# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::WalletTransactions::PaymentFailureAfterSettlementService do
  subject(:webhook_service) { described_class.new(object: wallet_transaction) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet:, status: "settled") }

  describe ".call" do
    it_behaves_like "creates webhook", "wallet_transaction.payment_failure_after_settlement", "wallet_transaction",
      {"lago_id" => String, "wallet" => Hash}
  end
end
