# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Hubspot::SavePortalIdJob, type: :job do
  describe '#perform' do
    subject(:job) { described_class }

    let(:service) { instance_double(Integrations::Hubspot::SavePortalIdService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Hubspot::SavePortalIdService).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_return(result)
    end

    it 'saves portal id to the integration' do
      described_class.perform_now(integration:)

      expect(Integrations::Hubspot::SavePortalIdService).to have_received(:new)
      expect(service).to have_received(:call)
    end
  end
end
