# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::Objects::DeployInvoicesJob, type: :job do
  describe '#perform' do
    subject(:deploy_invoices_job) { described_class }

    let(:deploy_invoices_service) { instance_double(Integrations::Hubspot::Objects::DeployInvoicesService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Hubspot::Objects::DeployInvoicesService).to receive(:new).and_return(deploy_invoices_service)
      allow(deploy_invoices_service).to receive(:call).and_return(result)
    end

    it 'calls the DeployInvoicesService to deploy invoices' do
      described_class.perform_now(integration:)

      expect(Integrations::Hubspot::Objects::DeployInvoicesService).to have_received(:new)
      expect(deploy_invoices_service).to have_received(:call)
    end
  end
end
