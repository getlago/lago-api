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

      context "with organization" do
        let(:other_organization_wallet) { create(:wallet, ready_to_be_refreshed: true) }

        before { other_organization_wallet }

        it "refreshes only wallets for the given organization" do
          described_class.perform_now(organization:)

          expect(Wallets::RefreshOngoingBalanceJob).to have_been_enqueued.with(wallet)
          expect(Wallets::RefreshOngoingBalanceJob).not_to have_been_enqueued.with(other_organization_wallet)
        end
      end

      context "when JobOverride is enabled for the wallet organization" do
        let(:job_schedule_override) do
          create(
            :job_schedule_override,
            organization:,
            job_name: described_class.name
          )
        end

        let(:other_organization_wallet) do
          create(:wallet, ready_to_be_refreshed: true)
        end

        before do
          other_organization_wallet
          job_schedule_override
        end

        it "does not call the refresh service for the wallet" do
          described_class.perform_now
          expect(Wallets::RefreshOngoingBalanceJob).not_to have_been_enqueued.with(wallet)
          expect(Wallets::RefreshOngoingBalanceJob).to have_been_enqueued.with(other_organization_wallet)
        end
      end
    end
  end
end
