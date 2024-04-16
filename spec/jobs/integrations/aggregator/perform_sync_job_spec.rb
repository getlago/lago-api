# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::PerformSyncJob, type: :job do
  subject(:perform_sync_job) { described_class }

  let(:sync_service) { instance_double(Integrations::Aggregator::SyncService) }
  let(:integration) { create(:netsuite_integration) }
  let(:result) { BaseService::Result.new }

  before do
    allow(Integrations::Aggregator::SyncService).to receive(:new).and_return(sync_service)
    allow(sync_service).to receive(:call).and_return(result)
  end

  it 'calls the aggregator sync service' do
    described_class.perform_now(integration:)

    expect(Integrations::Aggregator::SyncService).to have_received(:new)
    expect(sync_service).to have_received(:call)
  end
end
