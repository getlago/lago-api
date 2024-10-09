# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::Subscriptions::DeployObjectJob, type: :job do
  describe '#perform' do
    subject(:deploy_object_job) { described_class }

    let(:deploy_object_service) { instance_double(Integrations::Hubspot::Subscriptions::DeployObjectService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Hubspot::Subscriptions::DeployObjectService).to receive(:new).and_return(deploy_object_service)
      allow(deploy_object_service).to receive(:call).and_return(result)
    end

    it 'calls the DeployObjectService to deploy subscription custom object' do
      deploy_object_job.perform_now(integration:)

      expect(Integrations::Hubspot::Subscriptions::DeployObjectService).to have_received(:new)
      expect(deploy_object_service).to have_received(:call)
    end
  end
end
