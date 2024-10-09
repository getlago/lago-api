# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::SyncCustomObjectsAndPropertiesJob, type: :job do
  describe '#perform' do
    subject(:sync_job) { described_class }

    let(:integration) { create(:hubspot_integration) }

    before do
      allow(Integrations::Hubspot::Subscriptions::DeployObjectJob).to receive(:perform_later)
      allow(Integrations::Hubspot::Invoices::DeployObjectJob).to receive(:perform_later)
      allow(Integrations::Hubspot::Companies::DeployPropertiesJob).to receive(:perform_later)
      allow(Integrations::Hubspot::Contacts::DeployPropertiesJob).to receive(:perform_later)
    end

    it 'schedules all jobs needed with the current integration' do
      sync_job.perform_now(integration: integration)

      expect(Integrations::Hubspot::Subscriptions::DeployObjectJob).to have_received(:perform_later).with(integration:)
      expect(Integrations::Hubspot::Invoices::DeployObjectJob).to have_received(:perform_later).with(integration:)
      expect(Integrations::Hubspot::Companies::DeployPropertiesJob).to have_received(:perform_later).with(integration:)
      expect(Integrations::Hubspot::Contacts::DeployPropertiesJob).to have_received(:perform_later).with(integration:)
    end
  end
end
