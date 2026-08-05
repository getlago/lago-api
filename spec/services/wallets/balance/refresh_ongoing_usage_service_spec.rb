# frozen_string_literal: true

RSpec.describe Wallets::Balance::RefreshOngoingUsageService do
  subject(:result) do
    described_class.call(wallet:, ongoing_usage_amount_cents:, skip_single_wallet_update:)
  end

  let(:wallet) do
    create(
      :wallet,
      customer:,
      depleted_ongoing_balance:,
      balance_cents: 1000,
      ongoing_balance_cents: 800,
      ongoing_usage_balance_cents: 200,
      credits_balance: 10.0,
      credits_ongoing_balance: 8.0,
      credits_ongoing_usage_balance: 2.0
    )
  end

  let(:depleted_ongoing_balance) { false }
  let(:skip_single_wallet_update) { false }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:ongoing_usage_amount_cents) { 1100 }

  describe ".call" do
    it "writes the precomputed ongoing usage onto the wallet" do
      expect { subject }
        .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(1100)
        .and change(wallet, :credits_ongoing_usage_balance).from(2.0).to(11.0)
        .and change(wallet, :ongoing_balance_cents).from(800).to(-100)
        .and change(wallet, :credits_ongoing_balance).from(8.0).to(-1.0)
    end

    it "returns the wallet" do
      expect(result.wallet).to eq(wallet)
    end

    context "when the wallet rate differs from 1" do
      let(:wallet) do
        create(:wallet, customer:, balance_cents: 1000, rate_amount: "2",
          ongoing_balance_cents: 800, ongoing_usage_balance_cents: 200,
          credits_balance: 5.0, credits_ongoing_balance: 4.0, credits_ongoing_usage_balance: 1.0)
      end

      it "converts cents to credits using the wallet rate" do
        expect { subject }
          .to change(wallet.reload, :ongoing_usage_balance_cents).from(200).to(1100)
          .and change(wallet, :credits_ongoing_usage_balance).from(1.0).to(5.5)
          .and change(wallet, :ongoing_balance_cents).from(800).to(-100)
          .and change(wallet, :credits_ongoing_balance).from(4.0).to(-0.5)
      end
    end

    context "when recalculated ongoing balance is less than 0" do
      let(:ongoing_usage_amount_cents) { 1100 }

      before do
        allow(Wallets::Balance::UpdateOngoingService).to receive(:call).and_call_original
      end

      context "when wallet is not depleted" do
        it "sends update params with depleted_ongoing_balance set to true" do
          subject

          expect(Wallets::Balance::UpdateOngoingService).to have_received(:call)
            .with(wallet: wallet, update_params: hash_including(depleted_ongoing_balance: true), skip_single_wallet_update: false)
        end
      end

      context "when wallet is depleted before the update" do
        let(:depleted_ongoing_balance) { true }

        it "doesn't send update params with depleted_ongoing_balance set to true" do
          subject

          expect(Wallets::Balance::UpdateOngoingService).to have_received(:call)
            .with(wallet: wallet, update_params: hash_excluding(:depleted_ongoing_balance), skip_single_wallet_update: false)
        end
      end
    end

    context "when ongoing balance becomes positive after being depleted" do
      let(:depleted_ongoing_balance) { true }
      let(:ongoing_usage_amount_cents) { 500 }

      before do
        allow(Wallets::Balance::UpdateOngoingService).to receive(:call).and_call_original
      end

      it "sends update params with depleted_ongoing_balance set to false" do
        subject

        expect(Wallets::Balance::UpdateOngoingService).to have_received(:call)
          .with(wallet: wallet, update_params: hash_including(depleted_ongoing_balance: false), skip_single_wallet_update: false)
      end
    end

    context "when skip_single_wallet_update is true" do
      let(:skip_single_wallet_update) { true }

      before do
        allow(Wallets::Balance::UpdateOngoingService).to receive(:call).and_call_original
      end

      it "forwards the flag to the update service" do
        subject

        expect(Wallets::Balance::UpdateOngoingService).to have_received(:call)
          .with(wallet: wallet, update_params: anything, skip_single_wallet_update: true)
      end
    end
  end
end
