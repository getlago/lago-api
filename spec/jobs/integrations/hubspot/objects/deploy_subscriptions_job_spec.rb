# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::Objects::DeploySubscriptionsJob, type: :job do
  describe '#perform' do
    subject(:deploy_subscriptions_job) { described_class }

    let(:deploy_subscriptions_service) { instance_double(Integrations::Hubspot::Objects::DeploySubscriptionsService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Hubspot::Objects::DeploySubscriptionsService).to receive(:new).and_return(deploy_subscriptions_service)
      allow(deploy_subscriptions_service).to receive(:call).and_return(result)
    end

    it 'calls the DeploySubscriptionsService to deploy subscription custom object' do
      deploy_subscriptions_job.perform_now(integration:)

      expect(Integrations::Hubspot::Objects::DeploySubscriptionsService).to have_received(:new)
      expect(deploy_subscriptions_service).to have_received(:call)
    end
  end
end
