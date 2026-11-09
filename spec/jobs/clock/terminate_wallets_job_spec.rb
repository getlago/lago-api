# frozen_string_literal: true

require "rails_helper"

describe Clock::TerminateWalletsJob, job: true do
  before_all do
    create_default(:organization)
    create_default(:customer)
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  let(:to_expire_wallet) do
    create(
      :wallet,
      status: "active",
      expiration_at: Time.zone.now - 40.days
    )
  end

  let(:to_keep_active_wallet) do
    create(
      :wallet,
      status: "active",
      expiration_at: Time.zone.now + 40.days
    )
  end

  before do
    to_expire_wallet
    to_keep_active_wallet
  end

  it "terminates the expired wallets" do
    described_class.perform_now

    expect(to_expire_wallet.reload.status).to eq("terminated")
    expect(to_keep_active_wallet.reload.status).to eq("active")
  end

  context "when the wallet invoices its usage on expiration", :premium do
    let(:balance_cents) { 1000 }
    let(:to_expire_wallet) do
      create(
        :wallet,
        status: "active",
        expiration_at: Time.zone.now - 40.days,
        invoice_usage_on_expiration: true,
        balance_cents:,
        credits_balance: balance_cents / 100.0
      )
    end

    let(:feature_flags) { ["invoice_usage_on_wallet_expiration"] }

    before { to_expire_wallet.organization.update!(feature_flags:) }

    it "enqueues its expiration instead of terminating it inline" do
      described_class.perform_now

      expect(Wallets::ExpireWithInvoicingJob).to have_been_enqueued.with(to_expire_wallet)
      expect(to_expire_wallet.reload.status).to eq("active")
    end

    context "when the feature flag is disabled" do
      let(:feature_flags) { [] }

      it "terminates it inline" do
        described_class.perform_now

        expect(Wallets::ExpireWithInvoicingJob).not_to have_been_enqueued
        expect(to_expire_wallet.reload.status).to eq("terminated")
      end
    end

    context "when the wallet has no credits left" do
      let(:balance_cents) { 0 }

      it "terminates it inline" do
        described_class.perform_now

        expect(Wallets::ExpireWithInvoicingJob).not_to have_been_enqueued
        expect(to_expire_wallet.reload.status).to eq("terminated")
      end
    end

    context "without a premium license", premium: false do
      it "terminates it inline" do
        described_class.perform_now

        expect(Wallets::ExpireWithInvoicingJob).not_to have_been_enqueued
        expect(to_expire_wallet.reload.status).to eq("terminated")
      end
    end
  end
end
