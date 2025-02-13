# frozen_string_literal: true

require "rails_helper"

describe Clock::RefreshWalletsOngoingBalanceJob, job: true do
  subject { described_class }

  describe ".perform" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:wallet) { create(:wallet, customer:, ready_to_be_refreshed: true) }

    before do
      wallet
      allow(Wallets::Balance::RefreshOngoingService).to receive(:call)
    end

    context "when freemium" do
      it "does not call the refresh service" do
        described_class.perform_now
        expect(Wallets::RefreshOngoingBalanceJob).not_to have_been_enqueued.with(wallet)
      end
    end

    context "when premium" do
      around { |test| lago_premium!(&test) }

      it "calls the refresh service" do
        described_class.perform_now
        expect(Wallets::RefreshOngoingBalanceJob).to have_been_enqueued.with(wallet)
      end

      context "when not ready to be refreshed" do
        let(:wallet) { create(:wallet, customer:, ready_to_be_refreshed: false) }

        it "does not call the refresh service" do
          described_class.perform_now
          expect(Wallets::RefreshOngoingBalanceJob).not_to have_been_enqueued.with(wallet)
        end
      end
    end
  end
end
