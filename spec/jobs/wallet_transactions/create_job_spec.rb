# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::CreateJob do
  subject(:create_job) { described_class }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:wallet) { create(:wallet, customer:) }
  let(:wallet_transaction_create_service) { instance_double(WalletTransactions::CreateFromParamsService) }
  let(:params) do
    {
      wallet_id: wallet.id,
      paid_credits: "1.00",
      granted_credits: "1.00",
      source: "manual",
      purchase_order_number: "PO-123"
    }
  end

  it "calls the WalletTransactions::CreateFromParamsService" do
    allow(WalletTransactions::CreateFromParamsService).to receive(:call!)

    described_class.perform_now(organization_id: organization.id, params:)

    expect(WalletTransactions::CreateFromParamsService).to have_received(:call!).with(organization:, params:)
  end

  it "creates wallet transactions with the purchase order number" do
    expect do
      described_class.perform_now(organization_id: organization.id, params:)
    end.to change(WalletTransaction, :count).by(2)

    expect(wallet.wallet_transactions.pluck(:purchase_order_number)).to match_array(%w[PO-123 PO-123])
  end

  describe "#lock_key_arguments" do
    let(:organization_id) { "org-123" }
    let(:wallet_id) { "wallet-456" }
    let(:params) do
      {
        wallet_id: wallet_id,
        paid_credits: "10.0",
        granted_credits: "3.0",
        source: :threshold
      }
    end

    context "when unique_transaction is true" do
      def lock_key_for(job_params)
        job = described_class.new
        allow(job).to receive(:arguments).and_return([{
          organization_id: organization_id,
          params: job_params,
          unique_transaction: true
        }])
        job.lock_key_arguments
      end

      it "keys an automatic top-up on the wallet and the source, ignoring the amount" do
        expect(lock_key_for(params)).to eq([organization_id, wallet_id, "threshold"])
      end

      it "keys two automatic top-ups of different amounts the same" do
        expect(lock_key_for(params)).to eq(lock_key_for(params.merge(paid_credits: "450.0")))
      end

      it "keys a manual top-up on the amounts" do
        expect(lock_key_for(params.merge(source: :manual))).to eq([
          organization_id,
          wallet_id,
          "10.0",
          "3.0"
        ])
      end
    end
  end
end
