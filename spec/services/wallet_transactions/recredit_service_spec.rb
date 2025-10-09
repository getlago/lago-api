# frozen_string_literal: true

require "rails_helper"

RSpec.describe WalletTransactions::RecreditService do
  subject(:service) { described_class.new(wallet_transaction:) }

  let(:wallet_transaction) { create(:wallet_transaction, wallet:) }

  context "when wallet is terminated" do
    let(:wallet) { create(:wallet, :terminated) }

    it "returns a failure" do
      result = service.call

      aggregate_failures do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.message).to eq("wallet_not_active")
      end
    end
  end

  context "when wallet is active" do
    let(:wallet) { create(:wallet, consumed_credits: 1.0) }

    it "recredits the wallet" do
      aggregate_failures do
        expect { service.call }.to change { wallet.reload.credits_balance }.from(0).to(1.0)

        expect(service.call).to be_success
      end
    end

    it "resets consumed credits of the wallet" do
      aggregate_failures do
        expect { service.call }.to change { wallet.reload.consumed_credits }.from(1.0).to(0)

        expect(service.call).to be_success
      end
    end
  end
end
