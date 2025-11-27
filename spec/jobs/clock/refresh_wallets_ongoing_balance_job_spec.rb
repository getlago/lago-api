# frozen_string_literal: true

require "rails_helper"

describe Clock::RefreshWalletsOngoingBalanceJob, job: true do
  describe "#perform" do
    subject { described_class.perform_now }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }
    let(:wallet) { create(:wallet, customer:, ready_to_be_refreshed: true) }
    let(:customer_without_wallet) { create(:customer, organization:) }

    let(:customer_with_terminated_wallet) do
      create(:customer, organization:) do |customer|
        create(:wallet, customer:)
        create(:wallet, customer:, ready_to_be_refreshed: true, status: :terminated)
      end
    end

    before do
      wallet
      customer_without_wallet
      customer_with_terminated_wallet
      allow(Customers::RefreshWalletsService).to receive(:call)
    end

    context "when freemium" do
      it "does not schedule refresh job" do
        subject
        expect(Customers::RefreshWalletJob).not_to have_been_enqueued
      end
    end

    context "when premium" do
      around { |test| lago_premium!(&test) }

      it "schedules refresh job for customers with active wallet awaiting refresh" do
        subject
        expect(Customers::RefreshWalletJob).to have_been_enqueued.with(customer)
      end

      it "does not schedule refresh job for customers with terminated wallet or not awaiting for refresh" do
        subject
        expect(Customers::RefreshWalletJob).not_to have_been_enqueued.with(customer_without_wallet)
        expect(Customers::RefreshWalletJob).not_to have_been_enqueued.with(customer_with_terminated_wallet)
      end
    end
  end
end
