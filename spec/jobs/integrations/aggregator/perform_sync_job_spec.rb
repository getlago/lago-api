# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::PerformSyncJob do
  before_all do
    create_default(:organization)
  end

  subject(:perform_sync_job) { described_class.perform_now(integration:, sync_items:) }

  let(:integration) { create(:netsuite_integration) }
  let(:result) { Integrations::Aggregator::SyncService::Result.new }

  context "with the aggregator services stubbed" do
    before do
      allow(Integrations::Aggregator::SyncService).to receive(:call).and_return(result)
      allow(Integrations::Aggregator::ItemsService).to receive(:call).and_return(result)

      perform_sync_job
    end

    context "when sync_items is true" do
      let(:sync_items) { true }

      it "calls the aggregator sync service" do
        expect(Integrations::Aggregator::SyncService).to have_received(:call)
      end

      it "calls the aggregator items service" do
        expect(Integrations::Aggregator::ItemsService).to have_received(:call)
      end
    end

    context "when sync_items is false" do
      let(:sync_items) { false }

      it "calls the aggregator sync service" do
        expect(Integrations::Aggregator::SyncService).to have_received(:call)
      end

      it "does not call the aggregator items service" do
        expect(Integrations::Aggregator::ItemsService).not_to have_received(:call)
      end
    end
  end

  context "when the QuickBooks integration is flagged with a realm id mismatch" do
    let(:integration) do
      create(:quickbooks_integration, settings: {realm_id: "1234567890", sandbox: false, realm_id_mismatch: true})
    end
    let(:sync_items) { true }

    it "fails on the first execution without any request to Nango or retry" do
      expect { perform_sync_job }
        .to raise_error(BaseService::ForbiddenFailure) { |error| expect(error.code).to eq("realm_id_changed") }

      expect(a_request(:any, /api.nango.dev/)).not_to have_been_made
      expect(described_class).not_to have_been_enqueued
    end
  end
end
