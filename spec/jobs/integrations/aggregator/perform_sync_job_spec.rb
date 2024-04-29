# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::PerformSyncJob, type: :job do
  subject(:perform_sync_job) { described_class }

  let(:sync_service) { instance_double(Integrations::Aggregator::SyncService) }
  let(:items_service) { instance_double(Integrations::Aggregator::ItemsService) }
  let(:tax_items_service) { instance_double(Integrations::Aggregator::TaxItemsService) }
  let(:integration) { create(:netsuite_integration) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::SyncService).to receive(:new).and_return(sync_service)
    allow(sync_service).to receive(:call).and_return(result)

    allow(Integrations::Aggregator::ItemsService).to receive(:new).and_return(items_service)
    allow(items_service).to receive(:call).and_return(result)

    allow(Integrations::Aggregator::TaxItemsService).to receive(:new).and_return(tax_items_service)
    allow(tax_items_service).to receive(:call).and_return(result)
  end

  it 'calls the aggregator sync service' do
    described_class.perform_now(integration:)

    aggregate_failures do
      expect(Integrations::Aggregator::SyncService).to have_received(:new)
      expect(sync_service).to have_received(:call)

      expect(Integrations::Aggregator::ItemsService).to have_received(:new)
      expect(items_service).to have_received(:call)

      expect(Integrations::Aggregator::TaxItemsService).to have_received(:new)
      expect(tax_items_service).to have_received(:call)
    end
  end
end
