# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::SyncCustomObjectsAndPropertiesJob, type: :job do
  describe '#perform' do
    subject(:sync_job) { described_class }

    let(:integration) { create(:hubspot_integration) }

    before do
      allow(Integrations::Hubspot::Objects::DeploySubscriptionsJob).to receive(:perform_later)
      allow(Integrations::Hubspot::Objects::DeployInvoicesJob).to receive(:perform_later)
      allow(Integrations::Hubspot::Properties::DeployCompaniesJob).to receive(:perform_later)
      allow(Integrations::Hubspot::Properties::DeployContactsJob).to receive(:perform_later)
    end

    it 'schedules all jobs needed with the current integration' do
      sync_job.perform_now(integration: integration)

      expect(Integrations::Hubspot::Objects::DeploySubscriptionsJob).to have_received(:perform_later).with(integration:)
      expect(Integrations::Hubspot::Objects::DeployInvoicesJob).to have_received(:perform_later).with(integration:)
      expect(Integrations::Hubspot::Properties::DeployCompaniesJob).to have_received(:perform_later).with(integration:)
      expect(Integrations::Hubspot::Properties::DeployContactsJob).to have_received(:perform_later).with(integration:)
    end
  end
end
