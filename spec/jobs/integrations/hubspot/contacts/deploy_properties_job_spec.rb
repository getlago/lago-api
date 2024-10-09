# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::Contacts::DeployPropertiesJob, type: :job do
  describe '#perform' do
    subject(:deploy_properties_job) { described_class }

    let(:deploy_contact_service) { instance_double(Integrations::Hubspot::Contacts::DeployPropertiesService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Hubspot::Contacts::DeployPropertiesService).to receive(:new).and_return(deploy_contact_service)
      allow(deploy_contact_service).to receive(:call).and_return(result)
    end

    it 'calls the DeployPropertiesService to sync contacts custom properties' do
      deploy_properties_job.perform_now(integration:)

      expect(Integrations::Hubspot::Contacts::DeployPropertiesService).to have_received(:new)
      expect(deploy_contact_service).to have_received(:call)
    end
  end
end
