# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::Properties::DeployContactsJob, type: :job do
  describe '#perform' do
    subject(:deploy_contact_job) { described_class }

    let(:deploy_contact_service) { instance_double(Integrations::Hubspot::Properties::DeployContactsService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Hubspot::Properties::DeployContactsService).to receive(:new).and_return(deploy_contact_service)
      allow(deploy_contact_service).to receive(:call).and_return(result)
    end

    it 'calls the DeployContactsService to deploy contacts' do
      described_class.perform_now(integration:)

      expect(Integrations::Hubspot::Properties::DeployContactsService).to have_received(:new)
      expect(deploy_contact_service).to have_received(:call)
    end
  end
end
