# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::Properties::DeployCompaniesJob, type: :job do
  describe '#perform' do
    subject(:deploy_companies_job) { described_class }

    let(:deploy_companies_service) { instance_double(Integrations::Hubspot::Properties::DeployCompaniesService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Hubspot::Properties::DeployCompaniesService).to receive(:new).and_return(deploy_companies_service)
      allow(deploy_companies_service).to receive(:call).and_return(result)
    end

    it 'calls the DeployCompaniesService to sync companies custom properties' do
      deploy_companies_job.perform_now(integration:)

      expect(Integrations::Hubspot::Properties::DeployCompaniesService).to have_received(:new)
      expect(deploy_companies_service).to have_received(:call)
    end
  end
end
