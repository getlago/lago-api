# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::DispatchCatalogWalletAlertsService do
  subject(:result) { described_class.call(catalog_wallet:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_wallet) { create(:catalog_wallet, organization:) }

  context "when premium", :premium do
    context "when the wallet has an alert" do
      before { create(:catalog_wallet_alert, organization:, catalog_wallet:) }

      it "enqueues the wallet's evaluation once the transaction commits" do
        expect { result }.to have_enqueued_job_after_commit(UsageMonitoring::ProcessCatalogWalletAlertsJob).with(catalog_wallet)
      end
    end

    context "when the wallet has no alert" do
      before { create(:catalog_wallet_alert, organization:) }

      it "dispatches nothing" do
        expect { result }.not_to have_enqueued_job(UsageMonitoring::ProcessCatalogWalletAlertsJob)
      end
    end
  end

  context "when freemium" do
    before { create(:catalog_wallet_alert, organization:, catalog_wallet:) }

    it "dispatches nothing" do
      expect { result }.not_to have_enqueued_job(UsageMonitoring::ProcessCatalogWalletAlertsJob)
    end
  end
end
