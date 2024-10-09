# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::Companies::DeployPropertiesJob, type: :job do
  describe '#perform' do
    subject(:deploy_properties_job) { described_class }

    let(:deploy_company_service) { instance_double(Integrations::Hubspot::Companies::DeployPropertiesService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Hubspot::Companies::DeployPropertiesService).to receive(:new).and_return(deploy_company_service)
      allow(deploy_company_service).to receive(:call).and_return(result)
    end

    it 'calls the DeployPropertiesService to sync companies custom properties' do
      deploy_properties_job.perform_now(integration:)
      expect(Integrations::Hubspot::Companies::DeployPropertiesService).to have_received(:new)
      expect(deploy_company_service).to have_received(:call)
    end
  end
end
