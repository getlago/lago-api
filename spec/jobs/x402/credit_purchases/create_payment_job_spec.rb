# frozen_string_literal: true

require "rails_helper"

describe X402::CreditPurchases::CreatePaymentJob, job: true do
  subject(:job) { described_class }

  let(:customer) { create(:customer) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet_transaction) { create(:wallet_transaction, wallet: create(:wallet, customer:), source: :x402) }
  let(:invoice) { create(:invoice, :credit, customer:) }
  let(:x402_connection) { create(:x402_connection, organization: customer.organization) }
  let(:settlement) { create(:x402_settlement, x402_connection:, customer:, subscription:, wallet_transaction:) }

  before do
    settlement
    allow(X402::Payments::CreateService).to receive(:call!)
  end

  it "pays the invoice with the purchase's settlement" do
    job.perform_now(invoice, wallet_transaction)

    expect(X402::Payments::CreateService).to have_received(:call!).with(settlement:, invoice:)
  end

  it "runs on the default queue" do
    expect(job.new(invoice, wallet_transaction).queue_name).to eq("default")
  end

  context "with the payments worker enabled" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SIDEKIQ_PAYMENTS").and_return("true")
    end

    it "runs on the payments queue" do
      expect(job.new(invoice, wallet_transaction).queue_name).to eq("payments")
    end
  end

  context "without a settlement for the purchase" do
    let(:settlement) { create(:x402_settlement, x402_connection:, customer:) }

    it "raises" do
      expect { job.perform_now(invoice, wallet_transaction) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
