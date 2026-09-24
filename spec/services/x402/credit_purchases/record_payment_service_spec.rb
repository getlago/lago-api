# frozen_string_literal: true

require "rails_helper"

RSpec.describe X402::CreditPurchases::RecordPaymentService do
  subject(:result) { described_class.call(invoice:, wallet_transaction:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "USD") }
  let(:wallet) { create(:wallet, customer:, currency: "USD", rate_amount: "0.01") }
  let(:wallet_transaction) { create(:wallet_transaction, wallet:, source: :x402, amount: "1.00", credit_amount: "100.0") }
  let(:invoice) { create(:invoice, :credit, organization:, customer:, currency: "USD", total_amount_cents: 100, payment_status: :pending) }
  let(:settlement) { create(:x402_settlement, organization:, customer:, subscription: create(:subscription, customer:), wallet_transaction:) }

  before { settlement }

  it "pays the credit invoice with an x402 payment carrying the transaction hash" do
    expect(result.payment).to have_attributes(payment_type: "x402", status: "succeeded", payable_payment_status: "succeeded", amount_cents: 100, provider_payment_id: settlement.transaction_hash)
    expect(invoice.reload.payment_status).to eq("succeeded")
  end
end
