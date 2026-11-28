# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::ProcessCatalogWalletAlertsJob do
  let_it_be(:catalog_wallet) { create(:catalog_wallet) }

  before { allow(UsageMonitoring::ProcessCatalogWalletAlertsService).to receive(:call!) }

  it_behaves_like "a configurable queue", "alerts_high_priority", "SIDEKIQ_ALERTS" do
    let(:arguments) { catalog_wallet }
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [catalog_wallet] }
  end

  context "when premium", :premium do
    it "evaluates the wallet's alerts" do
      described_class.perform_now(catalog_wallet)

      expect(UsageMonitoring::ProcessCatalogWalletAlertsService).to have_received(:call!).with(catalog_wallet:)
    end

    context "when the balance changes while a run evaluates" do
      # Its own wallet: the locks of other examples stay in Redis
      let(:changed_wallet) { create(:catalog_wallet) }

      around do |example|
        ActiveJob::Uniqueness.reset_manager!
        example.run
        ActiveJob::Uniqueness.test_mode!
      end

      before do
        allow(UsageMonitoring::ProcessCatalogWalletAlertsService).to receive(:call!) { described_class.perform_later(changed_wallet) }
      end

      it "drops the run that change enqueues, as v1 does" do
        described_class.perform_later(changed_wallet)
        job = ActiveJob::Base.deserialize(enqueued_jobs.last)

        expect { job.perform_now }.not_to have_enqueued_job(described_class)
      end
    end

    context "when the wallet was discarded after the dispatch" do
      # GlobalID loads records past their default scope, so the run finds the wallet and, its alerts deleted, nothing to do
      it "still runs instead of failing to load it" do
        described_class.perform_later(catalog_wallet)
        CatalogWallet.find(catalog_wallet.id).discard!

        expect { perform_enqueued_jobs }.not_to raise_error
        expect(UsageMonitoring::ProcessCatalogWalletAlertsService).to have_received(:call!).with(catalog_wallet:)
      end
    end
  end

  context "when freemium" do
    it "evaluates nothing" do
      described_class.perform_now(catalog_wallet)

      expect(UsageMonitoring::ProcessCatalogWalletAlertsService).not_to have_received(:call!)
    end
  end
end
