# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Balance::DecreaseService, type: :service do
  subject(:create_service) { described_class.new(wallet:, wallet_transaction:) }

  let(:wallet) do
    create(
      :wallet,
      balance_cents: 1000,
      ongoing_balance_cents: 800,
      credits_balance: 10.0,
      credits_ongoing_balance: 8.0
    )
  end
  let(:wallet_transaction) do
    create(:wallet_transaction, wallet:, amount: "4.5", credit_amount: credits_amount)
  end

  let(:credits_amount) { BigDecimal("4.5") }

  before do
    wallet
    wallet_transaction
    allow(Wallets::Balance::RefreshOngoingService).to receive(:call).and_call_original
  end

  describe ".call" do
    it "updates wallet balance" do
      expect { create_service.call }
        .to change(wallet.reload, :balance_cents).from(1000).to(550)
        .and change(wallet, :credits_balance).from(10.0).to(5.5)
    end

    it "updates wallet consumed status" do
      expect { create_service.call }
        .to change(wallet.reload, :consumed_credits).from(0).to(4.5)
        .and change(wallet, :consumed_amount_cents).from(0).to(450)
    end

    it "refreshes wallet ongoing balance" do
      expect { create_service.call }
        .to change(wallet.reload, :ongoing_balance_cents).from(800).to(550)
        .and change(wallet, :credits_ongoing_balance).from(8.0).to(5.5)
    end

    it "sends a `wallet.updated` webhook" do
      expect { create_service.call }
        .to have_enqueued_job(SendWebhookJob).with("wallet.updated", Wallet)
    end

    it "calls Wallets::Balance::RefreshOngoingService" do
      create_service.call
      expect(Wallets::Balance::RefreshOngoingService).to have_received(:call).with(wallet: wallet, include_generating_invoices: true)
    end
  end
end
