# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::Aggregator::SendPrivateAppTokenJob, type: :job do
  describe '#perform' do
    subject(:send_token_job) { described_class }

    let(:send_token_service) { instance_double(Integrations::Aggregator::SendPrivateAppTokenService) }
    let(:integration) { create(:hubspot_integration) }
    let(:result) { BaseService::Result.new }

    before do
      allow(Integrations::Aggregator::SendPrivateAppTokenService).to receive(:new).and_return(send_token_service)
      allow(send_token_service).to receive(:call).and_return(result)
    end

    it 'sends the private app token the hubspot' do
      described_class.perform_now(integration:)

      expect(Integrations::Aggregator::SendPrivateAppTokenService).to have_received(:new)
      expect(send_token_service).to have_received(:call)
    end
  end
end
